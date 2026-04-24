import Foundation
import SwiftData

/// 想法池 ViewModel
@Observable
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
    private let minimumRefreshAnimationDuration: TimeInterval = 0.45

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

    /// 已确认删除的 ideaId
    var confirmedCleanupIds: Set<UUID> = []

    /// 撤销栈
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

    /// 刷新想法池
    func refresh(newIdeaIds: Set<UUID> = []) async {
        do {
            ideas = try await taskManager.fetchIdeaPool()
            if !newIdeaIds.isEmpty {
                newlyAddedIdeaIds = newIdeaIds
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(2))
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
    func updateIdea(ideaId: UUID, title: String? = nil, category: String? = nil, estimatedMinutes: Int? = nil, note: String? = nil) async {
        do {
            if let idea = try await taskManager.fetchIdeaPoolTask(ideaId: ideaId) {
                if let title { idea.title = title }
                if let category { idea.category = category }
                if let estimatedMinutes { idea.estimatedMinutes = estimatedMinutes }
                if let note { idea.note = note }
                try await taskManager.updateIdea(idea)
            }
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
            if !isProject {
                idea.projectProgress = 0
                idea.projectProgressSummary = nil
                idea.projectProgressUpdatedAt = nil
            }
            try await taskManager.updateIdea(idea)
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
                    try await aiService.analyzeProjectProgress(projects: progressTargets)
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
        confirmedCleanupIds = []
        undoStack = []

        let inputs = ideas.map { idea in
            TaskRecommendationInput(
                id: idea.id,
                title: idea.title,
                category: idea.category,
                estimatedMinutes: idea.estimatedMinutes,
                attempted: idea.attempted,
                status: idea.status,
                isProject: idea.isProject
            )
        }

        do {
            let aiService = await makeAIService()
            let result = try await aiService.cleanupIdeaPool(tasks: inputs)

            let ideaIds = Set(ideas.map { $0.id })
            let validItems = result.items.filter { ideaIds.contains($0.taskId) }
            let filteredResult = CleanupResult(items: validItems, overallReason: result.overallReason)

            cleanupState = .loaded(filteredResult)
        } catch {
            cleanupState = .error(error.localizedDescription)
        }
    }

    func markCleanupItem(taskId: UUID) {
        confirmedCleanupIds.insert(taskId)
        undoStack.append(taskId)
    }

    func markAllCleanupItems() {
        guard let result = currentCleanupResult else { return }
        for item in result.items where !confirmedCleanupIds.contains(item.taskId) {
            confirmedCleanupIds.insert(item.taskId)
            undoStack.append(item.taskId)
        }
    }

    func undoLastCleanup() {
        guard let lastId = undoStack.popLast() else { return }
        confirmedCleanupIds.remove(lastId)
    }

    func executeCleanup() async {
        for ideaId in confirmedCleanupIds {
            do {
                try await taskManager.deleteFromIdeaPool(ideaId: ideaId)
            } catch {
                errorMessage = error.localizedDescription
            }
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
