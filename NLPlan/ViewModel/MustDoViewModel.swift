import Foundation

/// 必做项 ViewModel
@Observable
final class MustDoViewModel {

    var tasks: [TaskEntity] = []
    var errorMessage: String?

    /// 移回想法池后的回调（用于通知想法池刷新）
    var onDemotedToIdeaPool: (() async -> Void)?

    /// 想法池刷新回调（推荐后需要同步）
    var onIdeaPoolChanged: (() async -> Void)?

    // MARK: - AI 推荐

    /// 推荐策略
    enum RecommendationStrategy: String, CaseIterable, Identifiable {
        case quickWin = "quick_win"       // 快速完成优先
        case hardFirst = "hard_first"     // 高难度优先

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .quickWin: return "快速完成优先"
            case .hardFirst: return "高难度优先"
            }
        }
    }

    enum RecommendationState: Equatable {
        case idle
        case loading
        case loaded(RecommendationResult)
        case error(String)
    }

    var recommendationState: RecommendationState = .idle
    var recommendationStrategy: RecommendationStrategy = .quickWin

    /// 已加入的推荐项 taskId
    var acceptedRecommendationIds: Set<UUID> = []

    /// 每条推荐项的用户选择优先级
    var selectedPriorities: [UUID: TaskPriority] = [:]

    /// 当前推荐结果（便利访问）
    var currentRecommendations: RecommendationResult? {
        if case .loaded(let result) = recommendationState {
            return result
        }
        return nil
    }

    var isRecommendationLoading: Bool {
        recommendationState == .loading
    }

    var showRecommendationPanel: Bool {
        switch recommendationState {
        case .loading, .loaded, .error:
            return true
        case .idle:
            return false
        }
    }

    /// 所有推荐项是否都已加入
    var allRecommendationsAccepted: Bool {
        guard let recs = currentRecommendations else { return false }
        return recs.recommendations.allSatisfy { acceptedRecommendationIds.contains($0.taskId) }
    }

    private let taskManager: TaskManager

    init(taskManager: TaskManager) {
        self.taskManager = taskManager
    }

    // MARK: - 必做项操作

    /// 刷新必做项列表
    func refresh() async {
        do {
            tasks = try await taskManager.fetchMustDo()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 开始执行任务
    func startTask(taskId: UUID) async {
        do {
            try await taskManager.startTask(taskId: taskId)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 标记完成
    func markComplete(taskId: UUID) async {
        do {
            try await taskManager.markComplete(taskId: taskId)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 移回想法池
    func demoteToIdeaPool(taskId: UUID) async {
        do {
            try await taskManager.demoteToIdeaPool(taskId: taskId)
            await refresh()
            await onDemotedToIdeaPool?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 已完成的任务
    var completedTasks: [TaskEntity] {
        tasks.filter { $0.status == TaskStatus.done.rawValue }
    }

    /// 未完成的任务（按优先级排序：高 → 中 → 低）
    var pendingTasks: [TaskEntity] {
        let priorityOrder: [String: Int] = [
            TaskPriority.high.rawValue: 0,
            TaskPriority.medium.rawValue: 1,
            TaskPriority.low.rawValue: 2
        ]
        return tasks
            .filter { $0.status != TaskStatus.done.rawValue }
            .sorted { (priorityOrder[$0.priority] ?? 1) < (priorityOrder[$1.priority] ?? 1) }
    }

    /// 正在运行的任务
    var runningTask: TaskEntity? {
        tasks.first { $0.status == TaskStatus.running.rawValue }
    }

    // MARK: - AI 推荐

    /// 获取 AI 推荐
    func fetchRecommendations(
        ideaPoolTasks: [TaskEntity],
        remainingHours: Double
    ) async {
        recommendationState = .loading
        errorMessage = nil
        acceptedRecommendationIds = []
        selectedPriorities = [:]

        let ideaInputs = ideaPoolTasks.map { task in
            TaskRecommendationInput(
                id: task.id,
                title: task.title,
                category: task.category,
                estimatedMinutes: task.estimatedMinutes,
                attempted: task.attempted,
                status: task.status
            )
        }

        let mustDoInputs = tasks.map { task in
            TaskRecommendationInput(
                id: task.id,
                title: task.title,
                category: task.category,
                estimatedMinutes: task.estimatedMinutes,
                attempted: task.attempted,
                status: task.status
            )
        }

        do {
            let aiService = await makeAIService()
            let result = try await aiService.recommendTasks(
                ideaPoolTasks: ideaInputs,
                mustDoTasks: mustDoInputs,
                remainingHours: remainingHours,
                strategy: recommendationStrategy
            )

            // 过滤掉不存在的 taskId
            let ideaIds = Set(ideaPoolTasks.map { $0.id })
            let validRecs = result.recommendations.filter { ideaIds.contains($0.taskId) }
            let filteredResult = RecommendationResult(
                recommendations: validRecs,
                overallReason: result.overallReason
            )

            // 设置默认优先级：按推荐顺序递减
            for (index, rec) in validRecs.enumerated() {
                let priority: TaskPriority
                switch index {
                case 0: priority = .high
                case 1: priority = .medium
                default: priority = .low
                }
                selectedPriorities[rec.taskId] = priority
            }

            recommendationState = .loaded(filteredResult)
        } catch {
            recommendationState = .error(error.localizedDescription)
        }
    }

    /// 接受单条推荐
    func acceptRecommendation(taskId: UUID) async {
        let priority = selectedPriorities[taskId] ?? .medium
        let order = currentRecommendations?.recommendations.firstIndex(where: { $0.taskId == taskId }) ?? 0
        do {
            try await taskManager.promoteToMustDo(taskId: taskId, priority: priority, sortOrder: order)
            acceptedRecommendationIds.insert(taskId)
            await refresh()
            await onIdeaPoolChanged?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 接受所有未操作的推荐
    func acceptAllRecommendations() async {
        guard let recs = currentRecommendations else { return }
        for (index, rec) in recs.recommendations.enumerated() {
            if !acceptedRecommendationIds.contains(rec.taskId) {
                let priority = selectedPriorities[rec.taskId] ?? .medium
                do {
                    try await taskManager.promoteToMustDo(taskId: rec.taskId, priority: priority, sortOrder: index)
                    acceptedRecommendationIds.insert(rec.taskId)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
        await refresh()
        await onIdeaPoolChanged?()
    }

    /// 关闭推荐面板
    func dismissRecommendations() {
        recommendationState = .idle
        acceptedRecommendationIds = []
    }

    // MARK: - Private

    private func makeAIService() async -> AIServiceProtocol {
        let apiKey = KeychainStore.shared.load(key: AppConstants.apiKeyKeychainKey) ?? ""
        let model = UserDefaults.standard.string(forKey: AppConstants.selectedModelKey) ?? AppConstants.defaultModel
        return DeepSeekAIService(apiKey: apiKey, model: model)
    }
}
