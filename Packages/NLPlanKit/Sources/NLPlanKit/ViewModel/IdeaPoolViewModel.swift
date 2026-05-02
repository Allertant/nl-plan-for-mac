import Foundation
import SwiftData
import SwiftUI

/// 想法池聚合展示项
enum IdeaPoolListItem: Identifiable {
    case idea(IdeaEntity)
    case project(ProjectEntity)

    var id: UUID {
        switch self {
        case .idea(let idea): return idea.id
        case .project(let project): return project.id
        }
    }

    var title: String {
        switch self {
        case .idea(let idea): return idea.title
        case .project(let project): return project.title
        }
    }

    var category: String {
        switch self {
        case .idea(let idea): return idea.category
        case .project(let project): return project.category
        }
    }

    var isProject: Bool {
        if case .project = self { return true }
        return false
    }

    var createdDate: Date {
        switch self {
        case .idea(let idea): return idea.createdDate
        case .project(let project): return project.createdDate
        }
    }

    var isPinned: Bool {
        switch self {
        case .idea(let idea): return idea.isPinned
        case .project(let project): return project.isPinned
        }
    }

    var pinnedAt: Date? {
        switch self {
        case .idea(let idea): return idea.pinnedAt
        case .project(let project): return project.pinnedAt
        }
    }
}

/// 想法池 ViewModel
@MainActor @Observable
final class IdeaPoolViewModel {

    enum ProjectDecisionSource: String {
        case ai
        case user
    }

    var ideas: [IdeaEntity] = []
    var projects: [ProjectEntity] = []
    var isExpanded: Bool = false

    /// pending 项目安排总数（由 refresh() 更新）
    private var pendingArrangementCount: Int = 0

    /// 待处理数量：pending 想法（实时计算）+ pending 项目安排
    var pendingCount: Int {
        ideas.filter { $0.status == IdeaStatus.pending.rawValue }.count
        + pendingArrangementCount
    }
    var errorMessage: String?
    var newlyAddedIdeaIds: Set<UUID> = []
    var isRefreshingProjects: Bool = false
    var refreshingProjectIds: Set<UUID> = []
    var generatingPlanningPromptIdeaIds: Set<UUID> = []
    var promotingArrangementIds: Set<UUID> = []
    private let minimumRefreshAnimationDuration: TimeInterval = 0.45

    /// 提升到必做项后的回调（用于通知必做项刷新）
    var onPromotedToMustDo: (() async -> Void)?

    // MARK: - 删除确认

    var pendingDeleteIdeaId: UUID?
    var pendingDeleteProjectId: UUID?

    var pendingDeleteIdeaTitle: String? {
        if let id = pendingDeleteIdeaId {
            return ideas.first(where: { $0.id == id })?.title
        }
        if let id = pendingDeleteProjectId {
            return projects.first(where: { $0.id == id })?.title
        }
        return nil
    }

    func requestDelete(ideaId: UUID) {
        pendingDeleteIdeaId = ideaId
    }

    func requestDeleteProject(projectId: UUID) {
        pendingDeleteProjectId = projectId
    }

    func cancelDelete() {
        pendingDeleteIdeaId = nil
        pendingDeleteProjectId = nil
    }

    func executeDelete() async {
        if let ideaId = pendingDeleteIdeaId {
            pendingDeleteIdeaId = nil
            await deleteIdea(ideaId: ideaId)
        } else if let projectId = pendingDeleteProjectId {
            pendingDeleteProjectId = nil
            await deleteProject(projectId: projectId)
        }
    }

    func promoteProjectToMustDo(projectId: UUID, priority: TaskPriority = .medium) async {
        do {
            _ = try await taskManager.createMustDoTask(
                title: projects.first(where: { $0.id == projectId })?.title ?? "项目任务",
                category: projects.first(where: { $0.id == projectId })?.category ?? "",
                estimatedMinutes: 30,
                priority: priority,
                sourceProjectId: projectId
            )
            await refresh()
            await onPromotedToMustDo?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteProject(projectId: UUID) async {
        do {
            try await taskManager.deleteProject(projectId: projectId)
            await refresh()
            await onPromotedToMustDo?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - 清理状态

    enum CleanupState: Equatable {
        case idle
        case loading
        case loaded(CleanupResult)
        case error(String)
    }

    var cleanupState: CleanupState = .idle

    var pendingDeleteCleanupId: UUID?

    var pendingDeleteCleanupTitle: String? {
        guard let id = pendingDeleteCleanupId else { return nil }
        return ideas.first(where: { $0.id == id })?.title
    }

    private var removedCleanupItems: [CleanupSuggestion] = []
    private var highlightClearTask: Task<Void, Never>?

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
    func refresh(newIdeaIds: Set<UUID> = [], animated: Bool = false) async {
        do {
            let fetchedIdeas = try await taskManager.fetchIdeaPool()
            let fetchedProjects = (try? await taskManager.fetchVisibleProjects()) ?? []
            let fetchedPendingArrangementCount = (try? await taskManager.fetchAllPendingArrangements().count) ?? 0
            if animated {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    ideas = fetchedIdeas
                    projects = fetchedProjects
                    pendingArrangementCount = fetchedPendingArrangementCount
                }
            } else {
                ideas = fetchedIdeas
                projects = fetchedProjects
                pendingArrangementCount = fetchedPendingArrangementCount
            }
            try? await repairStaleInProgressIdeas()
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
            await onPromotedToMustDo?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 更新想法字段
    func updateIdea(ideaId: UUID, title: String? = nil, category: String? = nil, estimatedMinutes: Int? = nil, note: String? = nil, deadline: Date? = nil) async {
        do {
            if let idea = try await taskManager.fetchIdeaPoolTask(ideaId: ideaId) {
                if let title { idea.title = title }
                if let category { idea.category = category }
                if let estimatedMinutes { idea.estimatedMinutes = estimatedMinutes }
                if let note { idea.note = note }
                if let deadline { idea.deadline = deadline }
                try await taskManager.updateIdea(idea)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateProject(projectId: UUID, title: String? = nil, category: String? = nil, deadline: Date? = nil) async {
        do {
            guard let project = try await taskManager.fetchProject(id: projectId) else { return }
            if let title { project.title = title }
            if let category { project.category = category }
            if let deadline { project.deadline = deadline }
            try await taskManager.updateProject(project)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func togglePin(for item: IdeaPoolListItem) async {
        do {
            switch item {
            case .idea(let idea):
                try await taskManager.toggleIdeaPin(ideaId: idea.id)
            case .project(let project):
                try await taskManager.toggleProjectPin(projectId: project.id)
            }
            await refresh(animated: true)
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

    func fetchLinkedMustDoTasks(sourceProjectId: UUID) async -> [DailyTaskEntity] {
        do {
            return try await taskManager.fetchMustDo(sourceProjectId: sourceProjectId)
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

    func refreshProjectRecommendationSummary(projectId: UUID) async {
        do {
            try await taskManager.refreshProjectRecommendationSummary(projectId: projectId)
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

    func fetchSettledTasks(sourceProjectId: UUID) async -> [DailyTaskEntity] {
        do {
            return try await taskManager.fetchSettledTasks(sourceProjectId: sourceProjectId)
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    func updateProjectNote(noteId: UUID, content: String) async {
        do {
            try await taskManager.updateProjectNote(noteId: noteId, content: content)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshProjectAnalyses(projectId: UUID? = nil) async {
        if let projectId {
            guard !isRefreshingProjects, !refreshingProjectIds.contains(projectId) else { return }
            refreshingProjectIds.insert(projectId)
        } else {
            guard !isRefreshingProjects, refreshingProjectIds.isEmpty else { return }
            isRefreshingProjects = true
        }
        let startedAt = Date()

        do {
            let allProjects = projects
            let allMustDos = try await taskManager.fetchMustDo()
            let aiService = await makeAIService()

            let targetProjects = allProjects.filter { project in
                guard let projectId else { return true }
                return project.id == projectId
            }

            let progressTargets = targetProjects.compactMap { project -> ProjectProgressInput? in
                let linkedMustDos = allMustDos.filter { $0.sourceProjectId == project.id || $0.sourceIdeaId == project.id }
                let completed = linkedMustDos.filter { $0.taskStatus == .done }
                let pending = linkedMustDos.filter { $0.taskStatus != .done }

                guard !completed.isEmpty else {
                    project.projectProgress = 0
                    project.projectProgressSummary = nil
                    project.projectProgressUpdatedAt = nil
                    return nil
                }

                return ProjectProgressInput(
                    ideaId: project.id,
                    title: project.title,
                    category: project.category,
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

                for project in targetProjects {
                    guard let analysis = analysisMap[project.id] else { continue }
                    project.projectProgress = min(max(analysis.progress, 0), 100)
                    project.projectProgressSummary = analysis.summary
                    project.projectProgressUpdatedAt = .now
                }
            }

            if let first = targetProjects.first {
                try await taskManager.updateProject(first)
            }
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }

        await finishProjectRefresh(projectId: projectId, startedAt: startedAt)
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
                isProject: false,
                projectDescription: nil,
                planningBackground: nil,
                projectRecommendationSummary: nil,
                deadlineDisplay: idea.deadlineDisplayString,
                note: idea.note,
                projectNotes: [],
                elapsedMinutes: 0,
                arrangementId: nil,
                projectTitle: nil
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

    // MARK: - 项目安排

    var arrangements: [ProjectArrangementEntity] = []

    enum PendingArrangementAction {
        case delete
        case revive
    }

    var pendingArrangementId: UUID?
    var pendingArrangementAction: PendingArrangementAction?

    var pendingArrangementTitle: String? {
        guard let id = pendingArrangementId else { return nil }
        return arrangements.first(where: { $0.id == id })?.content
    }

    func fetchArrangements(projectId: UUID) async {
        do {
            arrangements = try await taskManager.fetchArrangements(projectId: projectId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addArrangement(projectId: UUID, content: String, estimatedMinutes: Int = 30, deadline: Date? = nil) async {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let item = try await taskManager.addArrangement(
                projectId: projectId,
                content: trimmed,
                estimatedMinutes: estimatedMinutes,
                deadline: deadline
            )
            arrangements.append(item)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateArrangement(arrangementId: UUID, content: String? = nil, estimatedMinutes: Int? = nil, deadline: Date? = nil) async {
        guard let item = arrangements.first(where: { $0.id == arrangementId }) else { return }
        do {
            try await taskManager.updateArrangement(item, content: content, estimatedMinutes: estimatedMinutes, deadline: deadline)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateArrangementContent(arrangementId: UUID, content: String) async {
        guard let item = arrangements.first(where: { $0.id == arrangementId }) else { return }
        do {
            try await taskManager.updateArrangement(item, content: content)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func promoteArrangementToMustDo(arrangementId: UUID, priority: TaskPriority = .medium) async {
        guard !promotingArrangementIds.contains(arrangementId) else { return }
        promotingArrangementIds.insert(arrangementId)
        defer { promotingArrangementIds.remove(arrangementId) }

        do {
            _ = try await taskManager.promoteArrangementToMustDo(arrangementId: arrangementId, priority: priority)
            if let updated = try await taskManager.fetchArrangement(arrangementId) {
                if let index = arrangements.firstIndex(where: { $0.id == arrangementId }) {
                    arrangements[index] = updated
                } else {
                    arrangements.append(updated)
                }
            }
            await refresh()
            await onPromotedToMustDo?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func requestDeleteArrangement(id: UUID) {
        pendingArrangementId = id
        pendingArrangementAction = .delete
    }

    func requestReviveArrangement(id: UUID) {
        pendingArrangementId = id
        pendingArrangementAction = .revive
    }

    func cancelArrangementAction() {
        pendingArrangementId = nil
        pendingArrangementAction = nil
    }

    func executeArrangementAction(projectId: UUID) async {
        guard let id = pendingArrangementId,
              let action = pendingArrangementAction else { return }
        pendingArrangementId = nil
        pendingArrangementAction = nil

        switch action {
        case .delete:
            guard let item = arrangements.first(where: { $0.id == id }) else { return }
            do {
                try await taskManager.deleteArrangement(item)
                arrangements.removeAll { $0.id == id }
                await refresh()
            } catch {
                errorMessage = error.localizedDescription
            }

        case .revive:
            guard let item = arrangements.first(where: { $0.id == id }) else { return }
            do {
                try await taskManager.updateArrangementStatus(item, status: .pending)
                await refresh()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - ProjectEntity 路径

    func fetchProject(projectId: UUID) async -> ProjectEntity? {
        do {
            return try await taskManager.fetchProject(id: projectId)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func updateProjectTitle(projectId: UUID, title: String) async {
        do {
            try await taskManager.updateProjectTitle(projectId: projectId, title: title)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateProjectDescription(projectId: UUID, description: String?) async {
        do {
            try await taskManager.updateProjectDescription(projectId: projectId, description: description)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updatePlanningBackground(projectId: UUID, planningBackground: String?) async {
        do {
            try await taskManager.updatePlanningBackground(projectId: projectId, planningBackground: planningBackground)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func generatePlanningBackgroundPrompt(projectId: UUID) async {
        do {
            try await taskManager.generatePlanningBackgroundPrompt(projectId: projectId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addProjectNote(projectId: UUID, content: String) async {
        do {
            try await taskManager.addProjectNote(projectId: projectId, content: content)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func fetchProjectNotesByProjectId(projectId: UUID) async -> [ProjectNoteEntity] {
        do {
            return try await taskManager.fetchProjectNotesByProjectId(projectId: projectId)
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    // MARK: - Private

    private func repairStaleInProgressIdeas() async throws {
        for idea in ideas where idea.ideaStatus == .inProgress {
            let tasks = try await taskManager.fetchMustDo(sourceIdeaId: idea.id)
            let hasActive = tasks.contains { !$0.isSettled }
            if !hasActive {
                idea.ideaStatus = .pending
            }
        }
    }

    private func makeAIService() async -> AIServiceProtocol {
        let apiKey = KeychainStore.shared.load(key: AppConstants.apiKeyKeychainKey) ?? ""
        let model = AppConstants.normalizedModel(
            UserDefaults.standard.string(forKey: AppConstants.selectedModelKey)
        )
        let reasoningEffort = AppConstants.normalizedReasoningEffort(
            UserDefaults.standard.string(forKey: AppConstants.selectedReasoningEffortKey)
        )
        return DeepSeekAIService(apiKey: apiKey, model: model, reasoningEffort: reasoningEffort)
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

    private func finishProjectRefresh(projectId: UUID?, startedAt: Date) async {
        let elapsed = Date().timeIntervalSince(startedAt)
        if elapsed < minimumRefreshAnimationDuration {
            try? await Task.sleep(for: .seconds(minimumRefreshAnimationDuration - elapsed))
        }

        if let projectId {
            refreshingProjectIds.remove(projectId)
        } else {
            isRefreshingProjects = false
        }
    }
}
