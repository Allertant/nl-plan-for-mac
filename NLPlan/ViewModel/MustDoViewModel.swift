import Foundation

/// 必做项 ViewModel
@Observable
final class MustDoViewModel {

    var tasks: [DailyTaskEntity] = []
    var errorMessage: String?

    /// 耗时缓存 [taskId: seconds]
    var elapsedSecondsCache: [UUID: Int] = [:]

    /// 编辑模式（上下箭头排序）
    var isEditMode: Bool = false

    /// 移回想法池后的回调（用于通知想法池刷新）
    var onDemotedToIdeaPool: (() async -> Void)?

    /// 想法池刷新回调（推荐后需要同步）
    var onIdeaPoolChanged: (() async -> Void)?

    /// 项目来源绑定变化后的回调
    var onProjectLinkChanged: ((UUID?) async -> Void)?

    // MARK: - AI 推荐

    enum RecommendationStrategy: String, CaseIterable, Identifiable {
        case quickWin = "quick_win"
        case hardFirst = "hard_first"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .quickWin: return "快速完成优先"
            case .hardFirst: return "高难度优先"
            }
        }

        var shortName: String {
            switch self {
            case .quickWin: return "快速"
            case .hardFirst: return "挑战"
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

    /// 已加入的推荐项 id
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
        return recs.recommendations.allSatisfy { acceptedRecommendationIds.contains($0.id) }
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
            // 刷新耗时缓存
            elapsedSecondsCache.removeAll()
            for task in tasks {
                elapsedSecondsCache[task.id] = try await taskManager.totalElapsedSeconds(taskId: task.id)
            }
            reindexAllPendingSortOrders()
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

    /// 是否可以上移
    func canMoveUp(at index: Int) -> Bool {
        let pending = pendingTasks
        guard index > 0 && index < pending.count else { return false }
        return pending[index].priority == pending[index - 1].priority
    }

    /// 是否可以下移
    func canMoveDown(at index: Int) -> Bool {
        let pending = pendingTasks
        guard index >= 0 && index < pending.count - 1 else { return false }
        return pending[index].priority == pending[index + 1].priority
    }

    /// 上移
    func moveUp(at index: Int) {
        let pending = pendingTasks
        guard index > 0,
              pending[index].priority == pending[index - 1].priority else { return }

        let targetId = pending[index].id
        let priority = pending[index].priority
        var samePriority = pending.filter { $0.priority == priority }

        guard let localIdx = samePriority.firstIndex(where: { $0.id == targetId }),
              localIdx > 0 else { return }

        samePriority.swapAt(localIdx, localIdx - 1)
        reindexSortOrder(samePriority)
        Task { await refresh() }
    }

    /// 下移
    func moveDown(at index: Int) {
        let pending = pendingTasks
        guard index < pending.count - 1,
              pending[index].priority == pending[index + 1].priority else { return }

        let targetId = pending[index].id
        let priority = pending[index].priority
        var samePriority = pending.filter { $0.priority == priority }

        guard let localIdx = samePriority.firstIndex(where: { $0.id == targetId }),
              localIdx < samePriority.count - 1 else { return }

        samePriority.swapAt(localIdx, localIdx + 1)
        reindexSortOrder(samePriority)
        Task { await refresh() }
    }

    /// 已完成的任务
    var completedTasks: [DailyTaskEntity] {
        tasks.filter { $0.taskStatus == .done }
    }

    /// 未完成的任务（按优先级排序，同优先级内按 sortOrder）
    var pendingTasks: [DailyTaskEntity] {
        let priorityOrder: [String: Int] = [
            TaskPriority.high.rawValue: 0,
            TaskPriority.medium.rawValue: 1,
            TaskPriority.low.rawValue: 2
        ]
        return tasks
            .filter { $0.taskStatus != .done }
            .sorted {
                let p0 = priorityOrder[$0.priority] ?? 1
                let p1 = priorityOrder[$1.priority] ?? 1
                if p0 != p1 { return p0 < p1 }
                return $0.sortOrder < $1.sortOrder
            }
    }

    /// 正在运行的任务
    var runningTask: DailyTaskEntity? {
        tasks.first { $0.taskStatus == .running }
    }

    // MARK: - SortOrder 管理

    private func reindexSortOrder(_ tasks: [DailyTaskEntity]) {
        for (i, task) in tasks.enumerated() {
            task.sortOrder = i
        }
    }

    private func reindexAllPendingSortOrders() {
        let priorityOrder: [String: Int] = [
            TaskPriority.high.rawValue: 0,
            TaskPriority.medium.rawValue: 1,
            TaskPriority.low.rawValue: 2
        ]
        let sorted = tasks
            .filter { $0.taskStatus != .done }
            .sorted {
                let p0 = priorityOrder[$0.priority] ?? 1
                let p1 = priorityOrder[$1.priority] ?? 1
                if p0 != p1 { return p0 < p1 }
                return $0.sortOrder < $1.sortOrder
            }

        var counter = 0
        var currentPriority = ""
        for task in sorted {
            if task.priority != currentPriority {
                currentPriority = task.priority
                counter = 0
            }
            task.sortOrder = counter
            counter += 1
        }
    }

    // MARK: - AI 推荐

    func fetchRecommendations(
        ideaPoolIdeas: [IdeaEntity],
        remainingHours: Double
    ) async {
        recommendationState = .loading
        errorMessage = nil
        acceptedRecommendationIds = []
        selectedPriorities = [:]

        let recommendationCandidates = ideaPoolIdeas.filter { idea in
            idea.ideaStatus != .inProgress &&
            idea.ideaStatus != .completed &&
            idea.ideaStatus != .archived
        }

        let ideaInputs = recommendationCandidates.map { idea in
            TaskRecommendationInput(
                id: idea.id,
                title: idea.title,
                category: idea.category,
                estimatedMinutes: idea.estimatedMinutes,
                attempted: idea.attempted,
                status: idea.status,
                isProject: idea.isProject,
                projectDescription: idea.projectDescription
            )
        }

        let mustDoInputs = tasks.map { task in
            TaskRecommendationInput(
                id: task.id,
                title: task.title,
                category: task.category,
                estimatedMinutes: task.estimatedMinutes,
                attempted: task.attempted,
                status: task.status,
                isProject: false,
                projectDescription: nil
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

            let ideaIds = Set(recommendationCandidates.map { $0.id })
            let validRecs = result.recommendations.filter { recommendation in
                if let taskId = recommendation.taskId {
                    return ideaIds.contains(taskId)
                }
                if let sourceIdeaId = recommendation.sourceIdeaId {
                    return ideaIds.contains(sourceIdeaId)
                }
                return false
            }
            let filteredResult = RecommendationResult(
                recommendations: validRecs,
                overallReason: result.overallReason
            )

            for (index, rec) in validRecs.enumerated() {
                let priority: TaskPriority
                switch index {
                case 0: priority = .high
                case 1: priority = .medium
                default: priority = .low
                }
                selectedPriorities[rec.id] = priority
            }

            recommendationState = .loaded(filteredResult)
        } catch {
            recommendationState = .error(error.localizedDescription)
        }
    }

    func acceptRecommendation(recommendationId: UUID) async {
        guard let recommendation = currentRecommendations?.recommendations.first(where: { $0.id == recommendationId }) else {
            return
        }
        let priority = selectedPriorities[recommendation.id] ?? .medium
        let order = currentRecommendations?.recommendations.firstIndex(where: { $0.id == recommendation.id }) ?? 0
        do {
            try await applyRecommendation(recommendation, priority: priority, sortOrder: order)
            acceptedRecommendationIds.insert(recommendation.id)
            await refresh()
            await onIdeaPoolChanged?()
            await onProjectLinkChanged?(recommendation.sourceIdeaId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func acceptAllRecommendations() async {
        guard let recs = currentRecommendations else { return }
        for (index, rec) in recs.recommendations.enumerated() {
            if !acceptedRecommendationIds.contains(rec.id) {
                let priority = selectedPriorities[rec.id] ?? .medium
                do {
                    try await applyRecommendation(rec, priority: priority, sortOrder: index)
                    acceptedRecommendationIds.insert(rec.id)
                    await onProjectLinkChanged?(rec.sourceIdeaId)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
        await refresh()
        await onIdeaPoolChanged?()
    }

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

    private func applyRecommendation(_ recommendation: TaskRecommendation, priority: TaskPriority, sortOrder: Int) async throws {
        if let taskId = recommendation.taskId {
            try await taskManager.promoteToMustDo(ideaId: taskId, priority: priority, sortOrder: sortOrder)
        } else {
            _ = try await taskManager.createMustDoTask(
                title: recommendation.title,
                category: recommendation.category,
                estimatedMinutes: recommendation.estimatedMinutes,
                priority: priority,
                sortOrder: sortOrder,
                sourceIdeaId: recommendation.sourceIdeaId,
                recommendationReason: recommendation.reason
            )
        }
    }

    func updateSource(taskId: UUID, sourceIdeaId: UUID?) async {
        do {
            guard let task = try await taskManager.fetchMustDo(date: .now).first(where: { $0.id == taskId }) else { return }
            let previousSourceIdeaId = task.sourceIdeaId
            task.sourceIdeaId = sourceIdeaId
            try await taskManager.updateDailyTask(task)
            await refresh()
            await onProjectLinkChanged?(previousSourceIdeaId)
            if sourceIdeaId != previousSourceIdeaId {
                await onProjectLinkChanged?(sourceIdeaId)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
