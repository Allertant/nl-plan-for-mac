import Foundation

/// 必做项 ViewModel
@Observable
final class MustDoViewModel {
    private struct ProjectSummaryGenerationOutcome {
        let ideaId: UUID
        let summary: String?
        let sourceUpdatedAt: Date
    }

    var tasks: [DailyTaskEntity] = []
    var errorMessage: String?

    /// 耗时缓存 [taskId: seconds]
    var elapsedSecondsCache: [UUID: Int] = [:]

    // MARK: - 确认操作

    enum ConfirmAction: Equatable {
        case complete(UUID)
        case demote(UUID)
    }

    var pendingConfirm: ConfirmAction?

    var confirmTaskTitle: String? {
        guard let pending = pendingConfirm else { return nil }
        let id: UUID
        switch pending {
        case .complete(let taskId): id = taskId
        case .demote(let taskId): id = taskId
        }
        return tasks.first(where: { $0.id == id })?.title
    }

    func requestConfirm(_ action: ConfirmAction) {
        pendingConfirm = action
    }

    func cancelConfirm() {
        pendingConfirm = nil
    }

    func executeConfirm() async {
        guard let action = pendingConfirm else { return }
        pendingConfirm = nil
        switch action {
        case .complete(let taskId):
            await markComplete(taskId: taskId)
        case .demote(let taskId):
            await demoteToIdeaPool(taskId: taskId)
        }
    }

    /// 移回想法池后的回调（用于通知想法池刷新）
    var onDemotedToIdeaPool: (() async -> Void)?

    /// 想法池刷新回调（推荐后需要同步）
    var onIdeaPoolChanged: (() async -> Void)?

    /// 项目来源绑定变化后的回调
    var onProjectLinkChanged: ((UUID?) async -> Void)?

    // MARK: - AI 推荐

    enum RecommendationStrategy: String, CaseIterable, Identifiable {
        case quick = "quick"
        case comprehensive = "comprehensive"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .quick: return "快速推荐"
            case .comprehensive: return "综合推荐"
            }
        }

        var shortName: String {
            switch self {
            case .quick: return "快速"
            case .comprehensive: return "综合"
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
    var recommendationStrategy: RecommendationStrategy = .quick

    /// 推荐面板累计 token 用量
    var cumulativeTokenInput: Int = 0
    var cumulativeTokenOutput: Int = 0

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
    private let projectSummaryPreparationConcurrencyLimit = 2
    private let aiExecutionCoordinator = AIExecutionCoordinator()
    private var recommendationTask: Task<Void, Never>?
    private var checkpointTimer: Timer?

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
            updateCheckpointTimer()
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

    /// 暂停任务
    func pauseTask(taskId: UUID) async {
        do {
            try await taskManager.pauseTask(taskId: taskId)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 恢复任务
    func resumeTask(taskId: UUID) async {
        do {
            try await taskManager.resumeTask(taskId: taskId)
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
        remainingHours: Double,
        extraContext: String? = nil
    ) {
        recommendationTask?.cancel()
        let previousTask = recommendationTask
        errorMessage = nil
        acceptedRecommendationIds = []
        selectedPriorities = [:]
        cumulativeTokenInput = 0
        cumulativeTokenOutput = 0

        let allCandidates = ideaPoolIdeas.filter { idea in
            idea.ideaStatus != .inProgress &&
            idea.ideaStatus != .completed &&
            idea.ideaStatus != .archived
        }
        let strategy = recommendationStrategy
        let currentTasks = tasks

        recommendationTask = Task {
            // 等待上一个 Task 完成，避免并发修改状态
            _ = await previousTask?.result
            guard !Task.isCancelled else { return }

            recommendationState = .loading
            let recommendationCandidates: [IdeaEntity]
            switch strategy {
            case .quick:
                let nonProjectCandidates = allCandidates.filter { !$0.isProject }
                recommendationCandidates = nonProjectCandidates.isEmpty ? allCandidates : nonProjectCandidates
            case .comprehensive:
                do {
                    recommendationCandidates = try await prepareComprehensiveCandidates(from: allCandidates)
                } catch {
                    guard !Task.isCancelled else { return }
                    recommendationState = .error(error.localizedDescription)
                    return
                }
            }
            guard !Task.isCancelled else { return }

            var ideaInputs: [TaskRecommendationInput] = []
            for idea in recommendationCandidates {
                let projectNotes: [String]
                if idea.isProject {
                    projectNotes = (try? await taskManager.fetchProjectNotes(ideaId: idea.id))?.map(\.content) ?? []
                } else {
                    projectNotes = []
                }
                ideaInputs.append(TaskRecommendationInput(
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
                    projectNotes: projectNotes,
                    elapsedMinutes: 0
                ))
            }

            let mustDoInputs = currentTasks.map { task in
                let elapsed = elapsedSecondsCache[task.id].map { $0 / 60 } ?? 0
                let statusWithElapsed: String
                if task.taskStatus == .running || task.taskStatus == .paused {
                    statusWithElapsed = "\(task.status)(已用\(elapsed)分钟)"
                } else if task.taskStatus == .done {
                    statusWithElapsed = "已完成(实际\(task.actualMinutes ?? elapsed)分钟)"
                } else {
                    statusWithElapsed = task.status
                }
                return TaskRecommendationInput(
                    id: task.id,
                    title: task.title,
                    category: task.category,
                    estimatedMinutes: task.estimatedMinutes,
                    attempted: task.attempted,
                    status: statusWithElapsed,
                    isProject: false,
                    projectDescription: nil,
                    planningBackground: nil,
                    projectRecommendationSummary: nil,
                    deadlineDisplay: nil,
                    note: nil,
                    projectNotes: [],
                    elapsedMinutes: elapsed
                )
            }

            do {
                let aiService = await makeAIService()
                let result = try await aiExecutionCoordinator.run {
                    try await aiService.recommendTasks(
                    ideaPoolTasks: ideaInputs,
                    mustDoTasks: mustDoInputs,
                    remainingHours: remainingHours,
                    strategy: strategy,
                    extraContext: extraContext
                    )
                }
                guard !Task.isCancelled else { return }

                // 累计 token（推荐调用）
                if let usage = aiService.lastTokenUsage {
                    cumulativeTokenInput += usage.inputTokens
                    cumulativeTokenOutput += usage.outputTokens
                }

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
            } catch is CancellationError {
                // Silently ignore
            } catch {
                guard !Task.isCancelled else { return }
                recommendationState = .error(error.localizedDescription)
            }
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
        recommendationTask?.cancel()
        recommendationTask = nil
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

    private func prepareComprehensiveCandidates(from ideas: [IdeaEntity]) async throws -> [IdeaEntity] {
        let staleProjectIdeas = ideas.filter { $0.isProject && needsProjectRecommendationSummaryRefresh($0) }
        guard !staleProjectIdeas.isEmpty else { return ideas }

        var jobs: [ProjectRecommendationSummaryJob] = []
        for idea in staleProjectIdeas {
            if let job = try await taskManager.makeProjectRecommendationSummaryJob(ideaId: idea.id) {
                jobs.append(job)
            }
        }
        let aiService = await makeAIService()
        let refreshedIdeasById = try await generateProjectSummaries(jobs: jobs, aiService: aiService)
        return ideas.map { refreshedIdeasById[$0.id] ?? $0 }
    }

    private func generateProjectSummaries(
        jobs: [ProjectRecommendationSummaryJob],
        aiService: AIServiceProtocol
    ) async throws -> [UUID: IdeaEntity] {
        guard !jobs.isEmpty else { return [:] }

        var refreshedIdeasById: [UUID: IdeaEntity] = [:]
        let maxConcurrent = min(projectSummaryPreparationConcurrencyLimit, jobs.count)
        let executionCoordinator = aiExecutionCoordinator

        try await withThrowingTaskGroup(of: ProjectSummaryGenerationOutcome.self) { group in
            var nextIndex = 0

            func submitNextJob() {
                guard nextIndex < jobs.count else { return }
                let job = jobs[nextIndex]
                nextIndex += 1
                group.addTask {
                    do {
                        let result = try await executionCoordinator.run {
                            try await aiService.generateProjectRecommendationSummary(input: job.input)
                        }
                        return ProjectSummaryGenerationOutcome(
                            ideaId: job.ideaId,
                            summary: result.summary,
                            sourceUpdatedAt: job.contextUpdatedAt
                        )
                    } catch {
                        return ProjectSummaryGenerationOutcome(
                            ideaId: job.ideaId,
                            summary: nil,
                            sourceUpdatedAt: job.contextUpdatedAt
                        )
                    }
                }
            }

            for _ in 0..<maxConcurrent {
                submitNextJob()
            }

            while let outcome = try await group.next() {
                // 累计 token（项目摘要生成）
                if let usage = aiService.lastTokenUsage {
                    cumulativeTokenInput += usage.inputTokens
                    cumulativeTokenOutput += usage.outputTokens
                }
                if let summary = outcome.summary,
                   let refreshedIdea = try await taskManager.saveProjectRecommendationSummary(
                    ideaId: outcome.ideaId,
                    summary: summary,
                    sourceUpdatedAt: outcome.sourceUpdatedAt
                   ) {
                    refreshedIdeasById[outcome.ideaId] = refreshedIdea
                }
                submitNextJob()
            }
        }

        return refreshedIdeasById
    }

    private func needsProjectRecommendationSummaryRefresh(_ idea: IdeaEntity) -> Bool {
        guard idea.isProject else { return false }

        let summary = idea.projectRecommendationSummary?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let summary, !summary.isEmpty else { return true }

        guard let sourceUpdatedAt = idea.projectRecommendationSummarySourceUpdatedAt else {
            return true
        }

        let contextUpdatedAt = idea.projectRecommendationContextUpdatedAt ?? idea.updatedAt
        return sourceUpdatedAt < contextUpdatedAt
    }

    func updateSource(taskId: UUID, sourceIdeaId: UUID?) async {
        do {
            guard let task = try await taskManager.fetchMustDo(date: .now).first(where: { $0.id == taskId }) else { return }
            let previousSourceIdeaId = task.sourceIdeaId
            try await taskManager.rebindTaskSource(taskId: taskId, sourceIdeaId: sourceIdeaId)
            await refresh()
            await onProjectLinkChanged?(previousSourceIdeaId)
            if sourceIdeaId != previousSourceIdeaId {
                await onProjectLinkChanged?(sourceIdeaId)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateTaskNote(taskId: UUID, note: String) async {
        do {
            guard let task = try await taskManager.fetchMustDo(date: .now).first(where: { $0.id == taskId }) else { return }
            task.note = note.isEmpty ? nil : note
            try await taskManager.updateDailyTask(task)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Checkpoint Timer

    private func updateCheckpointTimer() {
        let hasRunningTasks = tasks.contains { $0.taskStatus == .running }
        if hasRunningTasks && checkpointTimer == nil {
            checkpointTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    try? await self.taskManager.checkpointRunningTasks()
                }
            }
        } else if !hasRunningTasks {
            checkpointTimer?.invalidate()
            checkpointTimer = nil
        }
    }

    // MARK: - Recovery

    /// 启动时恢复：将 running 状态的任务转为 paused
    func recoverRunningTasks() async throws {
        try await taskManager.recoverRunningTasksOnStartup()
        await refresh()
    }
}
