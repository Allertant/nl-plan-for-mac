import Foundation
import SwiftData

/// 想法池 ViewModel
@MainActor @Observable
final class IdeaPoolViewModel {

    enum ProjectDecisionSource: String {
        case ai
        case user
    }

    var ideas: [IdeaEntity] = []
    var isExpanded: Bool = false
    var errorMessage: String?
    var newlyAddedIdeaIds: Set<UUID> = []
    var isRefreshingProjects: Bool = false
    var refreshingProjectIds: Set<UUID> = []
    var generatingPlanningPromptIdeaIds: Set<UUID> = []
    private let minimumRefreshAnimationDuration: TimeInterval = 0.45

    /// 提升到必做项后的回调（用于通知必做项刷新）
    var onPromotedToMustDo: (() async -> Void)?

    // MARK: - 删除确认

    var pendingDeleteIdeaId: UUID?

    var pendingDeleteIdeaTitle: String? {
        guard let id = pendingDeleteIdeaId else { return nil }
        return ideas.first(where: { $0.id == id })?.title
    }

    func requestDelete(ideaId: UUID) {
        pendingDeleteIdeaId = ideaId
    }

    func cancelDelete() {
        pendingDeleteIdeaId = nil
    }

    func executeDelete() async {
        guard let ideaId = pendingDeleteIdeaId else { return }
        pendingDeleteIdeaId = nil
        await deleteIdea(ideaId: ideaId)
    }

    // MARK: - 清理状态

    enum CleanupState: Equatable {
        case idle
        case loading
        case loaded(CleanupResult)
        case error(String)
    }

    var cleanupState: CleanupState = .idle

    /// 待确认删除的清理项 ID
    var pendingDeleteCleanupId: UUID?

    /// 待确认删除的清理项标题
    var pendingDeleteCleanupTitle: String? {
        guard let id = pendingDeleteCleanupId else { return nil }
        return ideas.first(where: { $0.id == id })?.title
    }

    /// 延迟删除栈：已从 UI 移除但未从数据库删除的清理项（支持撤销）
    private var removedCleanupItems: [CleanupSuggestion] = []

    /// 高亮清除 Task（持有引用，新调用时取消旧的）
    private var highlightClearTask: Task<Void, Never>?

    /// 是否可以撤销
    var canUndoCleanup: Bool { !removedCleanupItems.isEmpty }

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

    private let taskManager: TaskManager
    private let aiExecutionCoordinator = AIExecutionCoordinator()

    init(taskManager: TaskManager) {
        self.taskManager = taskManager
    }

    /// 刷新想法池
    func refresh(newIdeaIds: Set<UUID> = []) async {
        do {
            ideas = try await taskManager.fetchIdeaPool()
            if !newIdeaIds.isEmpty {
                newlyAddedIdeaIds = newIdeaIds
                highlightClearTask?.cancel()
                highlightClearTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    self?.newlyAddedIdeaIds.removeAll()
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 加入必做项
    func promoteToMustDo(ideaId: UUID, priority: TaskPriority = .medium) async {
        do {
            try await taskManager.promoteToMustDo(ideaId: ideaId, priority: priority)
            await refresh()
            await onPromotedToMustDo?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 删除想法
    func deleteIdea(ideaId: UUID) async {
        do {
            try await taskManager.deleteFromIdeaPool(ideaId: ideaId)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 更新想法字段
    func updateIdea(ideaId: UUID, title: String? = nil, category: String? = nil, estimatedMinutes: Int? = nil, note: String? = nil, deadline: Date? = nil) async {
        do {
            if let idea = try await taskManager.fetchIdeaPoolTask(ideaId: ideaId) {
                let shouldTouchRecommendationContext = idea.isProject && (title != nil || category != nil || note != nil)
                if let title { idea.title = title }
                if let category { idea.category = category }
                if let estimatedMinutes, !idea.isProject { idea.estimatedMinutes = estimatedMinutes }
                if let note { idea.note = note }
                if let deadline { idea.deadline = deadline }
                try await taskManager.updateIdea(idea)
                if shouldTouchRecommendationContext {
                    try await taskManager.touchProjectRecommendationContext(ideaId: idea.id)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateProjectDescription(ideaId: UUID, description: String?) async {
        do {
            guard let idea = try await taskManager.fetchIdeaPoolTask(ideaId: ideaId) else { return }
            idea.projectDescription = normalizeOptionalText(description)
            try await taskManager.updateIdea(idea)
            try await taskManager.touchProjectRecommendationContext(ideaId: idea.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updatePlanningBackground(ideaId: UUID, planningBackground: String?) async {
        do {
            guard let idea = try await taskManager.fetchIdeaPoolTask(ideaId: ideaId) else { return }
            idea.planningBackground = normalizeOptionalText(planningBackground)
            try await taskManager.updateIdea(idea)
            try await taskManager.touchProjectRecommendationContext(ideaId: idea.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func generatePlanningBackgroundPrompt(ideaId: UUID) async {
        guard !generatingPlanningPromptIdeaIds.contains(ideaId) else { return }
        generatingPlanningPromptIdeaIds.insert(ideaId)
        defer { generatingPlanningPromptIdeaIds.remove(ideaId) }

        do {
            guard let idea = try await taskManager.fetchIdeaPoolTask(ideaId: ideaId) else { return }
            let activeTasks = try await taskManager.fetchMustDo(sourceIdeaId: ideaId)
            let settledTasks = try await taskManager.fetchSettledTasks(sourceIdeaId: ideaId)
            let notes = try await taskManager.fetchProjectNotes(ideaId: ideaId)
            let aiService = await makeAIService()

            let result = try await aiExecutionCoordinator.run {
                try await aiService.generatePlanningBackgroundPrompt(
                    input: PlanningBackgroundPromptInput(
                        title: idea.title,
                        category: idea.category,
                        estimatedMinutes: idea.estimatedMinutes,
                        attempted: idea.attempted,
                        projectDescription: idea.projectDescription,
                        planningBackground: idea.planningBackground,
                        notes: notes.map(\.content),
                        activeTasks: activeTasks.map { task in
                            "\(task.title) - \(task.taskStatus.displayName) - 预估\(task.estimatedMinutes)分钟"
                        },
                        settledTasks: settledTasks.map { task in
                            let reason = {
                                let t = task.incompletionReason?.trimmingCharacters(in: .whitespacesAndNewlines)
                                return (t != nil && !t!.isEmpty) ? t! : "无说明"
                            }()
                            return "\(task.title) - \(task.taskStatus == .done ? "已完成" : "未完成") - 未完成原因：\(reason)"
                        }
                    )
                )
            }

            idea.planningResearchPrompt = normalizeOptionalText(result.researchPrompt)
            idea.planningResearchPromptReason = normalizeOptionalText(result.reason)
            try await taskManager.updateIdea(idea)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func fetchLinkedMustDoTasks(sourceIdeaId: UUID) async -> [DailyTaskEntity] {
        do {
            return try await taskManager.fetchMustDo(sourceIdeaId: sourceIdeaId)
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    func fetchIdea(ideaId: UUID) async -> IdeaEntity? {
        do {
            return try await taskManager.fetchIdeaPoolTask(ideaId: ideaId)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func refreshProjectRecommendationSummary(ideaId: UUID) async {
        do {
            try await taskManager.refreshProjectRecommendationSummary(ideaId: ideaId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func fetchSettledTasks(sourceIdeaId: UUID) async -> [DailyTaskEntity] {
        do {
            return try await taskManager.fetchSettledTasks(sourceIdeaId: sourceIdeaId)
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    func fetchProjectNotes(ideaId: UUID) async -> [ProjectNoteEntity] {
        do {
            return try await taskManager.fetchProjectNotes(ideaId: ideaId)
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    func addProjectNote(ideaId: UUID, content: String) async {
        do {
            try await taskManager.addProjectNote(ideaId: ideaId, content: content)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateProjectNote(noteId: UUID, content: String) async {
        do {
            try await taskManager.updateProjectNote(noteId: noteId, content: content)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateProjectState(ideaId: UUID, isProject: Bool, source: ProjectDecisionSource = .user) async {
        do {
            guard let idea = try await taskManager.fetchIdeaPoolTask(ideaId: ideaId) else { return }
            idea.isProject = isProject
            idea.projectDecisionSource = source.rawValue
            idea.estimatedMinutes = isProject ? nil : (idea.estimatedMinutes ?? 30)
            if !isProject {
                idea.projectProgress = 0
                idea.projectProgressSummary = nil
                idea.projectProgressUpdatedAt = nil
            }
            try await taskManager.updateIdea(idea)
            if isProject {
                try await taskManager.touchProjectRecommendationContext(ideaId: idea.id)
            }
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshProjectAnalyses(ideaId: UUID? = nil) async {
        if let ideaId {
            guard !isRefreshingProjects, !refreshingProjectIds.contains(ideaId) else { return }
            refreshingProjectIds.insert(ideaId)
        } else {
            guard !isRefreshingProjects, refreshingProjectIds.isEmpty else { return }
            isRefreshingProjects = true
        }
        let startedAt = Date()

        do {
            let allIdeas = try await taskManager.fetchIdeaPool()
            let allMustDos = try await taskManager.fetchMustDo()
            let aiService = await makeAIService()

            let targetIdeas = allIdeas.filter { idea in
                guard let ideaId else { return true }
                return idea.id == ideaId
            }

            let progressTargets = targetIdeas.compactMap { idea -> ProjectProgressInput? in
                guard idea.isProject else { return nil }

                let linkedMustDos = allMustDos.filter { $0.sourceIdeaId == idea.id }
                let completed = linkedMustDos.filter { $0.taskStatus == .done }
                let pending = linkedMustDos.filter { $0.taskStatus != .done }

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
                    try await self.aiExecutionCoordinator.run {
                        try await aiService.analyzeProjectProgress(projects: progressTargets)
                    }
                }
                let analysisMap = Dictionary(uniqueKeysWithValues: analyses.map { ($0.ideaId, $0) })

                for idea in targetIdeas where idea.isProject {
                    guard let analysis = analysisMap[idea.id] else { continue }
                    idea.projectProgress = min(max(analysis.progress, 0), 100)
                    idea.projectProgressSummary = analysis.summary
                    idea.projectProgressUpdatedAt = .now
                }
            }

            if let first = targetIdeas.first {
                try await taskManager.updateIdea(first)
            }
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }

        await finishProjectRefresh(ideaId: ideaId, startedAt: startedAt)
    }

    // MARK: - AI 清理

    func fetchCleanupSuggestions() async {
        cleanupState = .loading
        errorMessage = nil
        removedCleanupItems = []

        let inputs = ideas.map { idea in
            TaskRecommendationInput(
                id: idea.id,
                title: idea.title,
                category: idea.category,
                estimatedMinutes: idea.estimatedMinutes,
                attempted: idea.attempted,
                status: idea.status,
                isProject: idea.isProject,
                projectDescription: idea.projectDescription,
                planningBackground: idea.planningBackground,
                projectRecommendationSummary: idea.projectRecommendationSummary,
                deadlineDisplay: idea.deadlineDisplayString,
                note: idea.note,
                projectNotes: [],
                elapsedMinutes: 0
            )
        }

        do {
            let aiService = await makeAIService()
            let result = try await aiExecutionCoordinator.run {
                try await aiService.cleanupIdeaPool(tasks: inputs)
            }

            let ideaIds = Set(ideas.map { $0.id })
            let validItems = result.items.filter { ideaIds.contains($0.taskId) }
            let filteredResult = CleanupResult(items: validItems, overallReason: result.overallReason)

            cleanupState = .loaded(filteredResult)
        } catch {
            cleanupState = .error(error.localizedDescription)
        }
    }

    func requestDeleteCleanup(taskId: UUID) {
        pendingDeleteCleanupId = taskId
    }

    func cancelDeleteCleanup() {
        pendingDeleteCleanupId = nil
    }

    func executeDeleteCleanup() async {
        guard let ideaId = pendingDeleteCleanupId else { return }
        pendingDeleteCleanupId = nil

        // 延迟删除：从 UI 列表移除并存入撤销栈，不立即删数据库
        if case .loaded(let result) = cleanupState {
            let removed = result.items.filter { $0.taskId == ideaId }
            removedCleanupItems.append(contentsOf: removed)
            let updated = result.items.filter { $0.taskId != ideaId }
            cleanupState = .loaded(CleanupResult(items: updated, overallReason: result.overallReason))
        }
        await refresh()
    }

    func markAllCleanupItems() {
        guard case .loaded(let result) = cleanupState else { return }
        removedCleanupItems.append(contentsOf: result.items)
        cleanupState = .loaded(CleanupResult(items: [], overallReason: result.overallReason))
    }

    func undoLastCleanup() {
        guard let entry = removedCleanupItems.popLast() else { return }
        if case .loaded(let result) = cleanupState {
            cleanupState = .loaded(CleanupResult(items: result.items + [entry], overallReason: result.overallReason))
        }
    }

    /// 离开页面：提交所有已确认的删除，真正从数据库删除
    func commitCleanupDeletes() async {
        let idsToDelete = removedCleanupItems.map(\.taskId)
        removedCleanupItems = []
        for ideaId in idsToDelete {
            try? await taskManager.deleteFromIdeaPool(ideaId: ideaId)
        }
        await refresh()
        resetCleanupState()
    }

    func skipCleanupItem(taskId: UUID) {
        guard case .loaded(let result) = cleanupState else { return }
        let updated = result.items.filter { $0.taskId != taskId }
        cleanupState = .loaded(CleanupResult(items: updated, overallReason: result.overallReason))
    }

    func resetCleanupState() {
        cleanupState = .idle
        removedCleanupItems = []
    }

    // MARK: - Private

    private func makeAIService() async -> AIServiceProtocol {
        let apiKey = KeychainStore.shared.load(key: AppConstants.apiKeyKeychainKey) ?? ""
        let model = UserDefaults.standard.string(forKey: AppConstants.selectedModelKey) ?? AppConstants.defaultModel
        return DeepSeekAIService(apiKey: apiKey, model: model)
    }

    private func normalizeOptionalText(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
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

    private func finishProjectRefresh(ideaId: UUID?, startedAt: Date) async {
        let elapsed = Date().timeIntervalSince(startedAt)
        if elapsed < minimumRefreshAnimationDuration {
            try? await Task.sleep(for: .seconds(minimumRefreshAnimationDuration - elapsed))
        }

        if let ideaId {
            refreshingProjectIds.remove(ideaId)
        } else {
            isRefreshingProjects = false
        }
    }
}
