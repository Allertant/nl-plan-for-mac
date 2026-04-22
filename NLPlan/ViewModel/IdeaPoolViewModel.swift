import Foundation
import SwiftData

/// 想法池 ViewModel
@Observable
final class IdeaPoolViewModel {

    enum ProjectDecisionSource: String {
        case ai
        case user
    }

    var tasks: [TaskEntity] = []
    var isExpanded: Bool = false
    var errorMessage: String?
    var newlyAddedTaskIds: Set<UUID> = []
    var isRefreshingProjects: Bool = false
    var refreshingProjectIds: Set<UUID> = []

    /// 提升到必做项后的回调（用于通知必做项刷新）
    var onPromotedToMustDo: (() async -> Void)?

    // MARK: - 清理状态

    enum CleanupState: Equatable {
        case idle
        case loading
        case loaded(CleanupResult)
        case error(String)
    }

    var cleanupState: CleanupState = .idle

    /// 已确认删除的 taskId
    var confirmedCleanupIds: Set<UUID> = []

    /// 撤销栈（按顺序记录已标记删除的 taskId）
    private var undoStack: [UUID] = []

    /// 是否可以撤销
    var canUndoCleanup: Bool { !undoStack.isEmpty }

    var showCleanupPanel: Bool {
        switch cleanupState {
        case .loading, .loaded, .error: return true
        case .idle: return false
        }
    }

    var currentCleanupResult: CleanupResult? {
        if case .loaded(let result) = cleanupState { return result }
        return nil
    }

    var allCleanupConfirmed: Bool {
        guard let result = currentCleanupResult else { return false }
        return result.items.allSatisfy { confirmedCleanupIds.contains($0.taskId) }
    }

    private let taskManager: TaskManager

    init(taskManager: TaskManager) {
        self.taskManager = taskManager
    }

    /// 刷新想法池（可传入新增任务 ID 用于高亮闪烁）
    func refresh(newTaskIds: Set<UUID> = []) async {
        do {
            tasks = try await taskManager.fetchIdeaPool()
            if !newTaskIds.isEmpty {
                newlyAddedTaskIds = newTaskIds
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(2))
                    self?.newlyAddedTaskIds.removeAll()
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 加入必做项
    func promoteToMustDo(taskId: UUID, priority: TaskPriority = .medium) async {
        do {
            try await taskManager.promoteToMustDo(taskId: taskId, priority: priority)
            await refresh()
            await onPromotedToMustDo?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 删除任务
    func deleteTask(taskId: UUID) async {
        do {
            try await taskManager.deleteFromIdeaPool(taskId: taskId)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 更新任务字段（标题/标签/时长/备注）
    func updateTask(taskId: UUID, title: String? = nil, category: String? = nil, estimatedMinutes: Int? = nil, note: String? = nil) async {
        do {
            if let task = try await taskManager.fetchIdeaPoolTask(taskId: taskId) {
                if let title { task.title = title }
                if let category { task.category = category }
                if let estimatedMinutes { task.estimatedMinutes = estimatedMinutes }
                if let note { task.note = note }
                try await taskManager.updateTask(task)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateProjectState(taskId: UUID, isProject: Bool, source: ProjectDecisionSource = .user) async {
        do {
            guard let task = try await taskManager.fetchIdeaPoolTask(taskId: taskId) else { return }
            task.isProject = isProject
            task.projectDecisionSource = source.rawValue
            if !isProject {
                task.projectProgress = 0
                task.projectProgressSummary = nil
                task.projectProgressUpdatedAt = nil
            }
            try await taskManager.updateTask(task)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshProjectAnalyses(taskId: UUID? = nil) async {
        if let taskId {
            guard !isRefreshingProjects, !refreshingProjectIds.contains(taskId) else { return }
            refreshingProjectIds.insert(taskId)
        } else {
            guard !isRefreshingProjects, refreshingProjectIds.isEmpty else { return }
            isRefreshingProjects = true
        }

        defer {
            if let taskId {
                refreshingProjectIds.remove(taskId)
            } else {
                isRefreshingProjects = false
            }
        }

        do {
            let allIdeas = try await taskManager.fetchIdeaPool()
            let allMustDos = try await taskManager.fetchMustDo()
            let aiService = await makeAIService()

            let targetIdeas = allIdeas.filter { idea in
                guard let taskId else { return true }
                return idea.id == taskId
            }

            let progressTargets = targetIdeas.compactMap { idea -> ProjectProgressInput? in
                guard idea.isProjectTask else { return nil }

                let linkedMustDos = allMustDos.filter { $0.sourceIdeaId == idea.id }
                let completed = linkedMustDos.filter { $0.status == TaskStatus.done.rawValue }
                let pending = linkedMustDos.filter { $0.status != TaskStatus.done.rawValue }

                guard !completed.isEmpty else {
                    idea.projectProgress = 0
                    idea.projectProgressSummary = nil
                    idea.projectProgressUpdatedAt = nil
                    return nil
                }

                return ProjectProgressInput(
                    ideaId: idea.id,
                    title: idea.title,
                    category: idea.category,
                    completedTasks: completed.map {
                        ProjectLinkedTaskInput(
                            id: $0.id,
                            title: $0.title,
                            estimatedMinutes: $0.estimatedMinutes,
                            completed: true
                        )
                    },
                    pendingTasks: pending.map {
                        ProjectLinkedTaskInput(
                            id: $0.id,
                            title: $0.title,
                            estimatedMinutes: $0.estimatedMinutes,
                            completed: false
                        )
                    }
                )
            }

            if !progressTargets.isEmpty {
                let analyses = try await withProjectAnalysisTimeout {
                    try await aiService.analyzeProjectProgress(projects: progressTargets)
                }
                let analysisMap = Dictionary(uniqueKeysWithValues: analyses.map { ($0.ideaId, $0) })

                for idea in targetIdeas where idea.isProjectTask {
                    guard let analysis = analysisMap[idea.id] else { continue }
                    idea.projectProgress = min(max(analysis.progress, 0), 100)
                    idea.projectProgressSummary = analysis.summary
                    idea.projectProgressUpdatedAt = .now
                }
            }

            if let first = targetIdeas.first {
                try await taskManager.updateTask(first)
            }
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - AI 清理

    /// 请求 AI 分析可清理的任务
    func fetchCleanupSuggestions() async {
        cleanupState = .loading
        errorMessage = nil
        confirmedCleanupIds = []
        undoStack = []

        let inputs = tasks.map { task in
            TaskRecommendationInput(
                id: task.id,
                title: task.title,
                category: task.category,
                estimatedMinutes: task.estimatedMinutes,
                attempted: task.attempted,
                status: task.status,
                isProject: task.isProjectTask
            )
        }

        do {
            let aiService = await makeAIService()
            let result = try await aiService.cleanupIdeaPool(tasks: inputs)

            // 过滤掉不存在的 taskId
            let taskIds = Set(tasks.map { $0.id })
            let validItems = result.items.filter { taskIds.contains($0.taskId) }
            let filteredResult = CleanupResult(items: validItems, overallReason: result.overallReason)

            cleanupState = .loaded(filteredResult)
        } catch {
            cleanupState = .error(error.localizedDescription)
        }
    }

    /// 标记单条为待删除（不执行数据库操作）
    func markCleanupItem(taskId: UUID) {
        confirmedCleanupIds.insert(taskId)
        undoStack.append(taskId)
    }

    /// 标记所有为待删除
    func markAllCleanupItems() {
        guard let result = currentCleanupResult else { return }
        for item in result.items where !confirmedCleanupIds.contains(item.taskId) {
            confirmedCleanupIds.insert(item.taskId)
            undoStack.append(item.taskId)
        }
    }

    /// 撤销上一次标记
    func undoLastCleanup() {
        guard let lastId = undoStack.popLast() else { return }
        confirmedCleanupIds.remove(lastId)
    }

    /// 执行批量删除（从数据库真正删除所有已标记项）
    func executeCleanup() async {
        for taskId in confirmedCleanupIds {
            do {
                try await taskManager.deleteFromIdeaPool(taskId: taskId)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        await refresh()
        resetCleanupState()
    }

    /// 跳过单条（从建议列表中移除，不删除）
    func skipCleanupItem(taskId: UUID) {
        guard case .loaded(let result) = cleanupState else { return }
        let updated = result.items.filter { $0.taskId != taskId }
        cleanupState = .loaded(CleanupResult(items: updated, overallReason: result.overallReason))
    }

    /// 重置清理状态（全部跳过时调用）
    func resetCleanupState() {
        cleanupState = .idle
        confirmedCleanupIds = []
        undoStack = []
    }

    // MARK: - Private

    private func makeAIService() async -> AIServiceProtocol {
        let apiKey = KeychainStore.shared.load(key: AppConstants.apiKeyKeychainKey) ?? ""
        let model = UserDefaults.standard.string(forKey: AppConstants.selectedModelKey) ?? AppConstants.defaultModel
        return DeepSeekAIService(apiKey: apiKey, model: model)
    }

    private func withProjectAnalysisTimeout<T: Sendable>(
        seconds: Double = 45,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw NLPlanError.aiRequestTimeout
            }

            guard let result = try await group.next() else {
                throw NLPlanError.aiRequestTimeout
            }
            group.cancelAll()
            return result
        }
    }
}
