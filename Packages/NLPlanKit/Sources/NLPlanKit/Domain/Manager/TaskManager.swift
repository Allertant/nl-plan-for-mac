import Foundation
import SwiftData

/// 任务生命周期管理
@MainActor
final class TaskManager {
    struct DailyTaskSourceLookup {
        let idea: IdeaEntity?
        let project: ProjectEntity?

        static let empty = DailyTaskSourceLookup(idea: nil, project: nil)
    }


    private let ideaRepo: IdeaRepository
    private let projectRepo: ProjectRepository
    private let dailyTaskRepo: DailyTaskRepository
    private let thoughtRepo: ThoughtRepository
    private let sessionLogRepo: SessionLogRepository
    private let arrangementRepo: ProjectArrangementRepository
    private let aiService: AIServiceProtocol
    private let timerEngine: TimerEngine
    private let aiExecutionCoordinator = AIExecutionCoordinator()

    /// 最近一次 AI 请求的 token 用量
    var lastTokenUsage: TokenUsage? { aiService.lastTokenUsage }

    init(
        ideaRepo: IdeaRepository,
        projectRepo: ProjectRepository,
        dailyTaskRepo: DailyTaskRepository,
        thoughtRepo: ThoughtRepository,
        sessionLogRepo: SessionLogRepository,
        arrangementRepo: ProjectArrangementRepository,
        aiService: AIServiceProtocol,
        timerEngine: TimerEngine
    ) {
        self.ideaRepo = ideaRepo
        self.projectRepo = projectRepo
        self.dailyTaskRepo = dailyTaskRepo
        self.thoughtRepo = thoughtRepo
        self.sessionLogRepo = sessionLogRepo
        self.arrangementRepo = arrangementRepo
        self.aiService = aiService
        self.timerEngine = timerEngine
    }

    // MARK: - 想法池操作

    /// 仅调用 AI 解析，不保存（供确认流程使用）
    func parseThoughts(rawText: String, existingTaskTitles: [String]) async throws -> [ParsedTask] {
        try await aiExecutionCoordinator.run {
            try await self.aiService.parseThoughts(
                input: rawText,
                existingTaskTitles: existingTaskTitles
            )
        }
    }

    /// 根据用户指令修改已解析的任务（供确认流程使用）
    func refineParsedTasks(
        originalInput: String,
        currentTasks: [ParsedTask],
        userInstruction: String
    ) async throws -> [ParsedTask] {
        try await aiExecutionCoordinator.run {
            try await self.aiService.refineTasks(
                originalInput: originalInput,
                currentTasks: currentTasks,
                userInstruction: userInstruction
            )
        }
    }

    /// 判断解析结果中的任务是否属于项目型想法
    func classifyProjects(tasks: [ProjectClassificationInput]) async throws -> [ProjectClassification] {
        try await aiExecutionCoordinator.run {
            try await self.aiService.classifyProjects(tasks: tasks)
        }
    }

    /// 将已解析的任务保存到想法池或项目表
    func saveParsedTasks(parsedTasks: [ParsedTask], rawText: String) async throws -> [UUID] {
        let thought = try thoughtRepo.create(rawText: rawText)

        var createdIds: [UUID] = []
        for (index, parsed) in parsedTasks.enumerated() {
            let isProject = parsed.isProject ?? false
            if isProject {
                let project = try projectRepo.create(
                    title: parsed.title,
                    category: parsed.category,
                    sortOrder: index,
                    projectDecisionSource: parsed.isProject != nil ? "ai" : nil,
                    deadline: parsed.deadline
                )
                createdIds.append(project.id)
            } else {
                let idea = try ideaRepo.create(
                    title: parsed.title,
                    category: parsed.category,
                    estimatedMinutes: parsed.estimatedMinutes,
                    aiRecommended: parsed.recommended,
                    recommendationReason: parsed.reason,
                    sortOrder: index,
                    note: parsed.note,
                    deadline: parsed.deadline
                )
                createdIds.append(idea.id)
            }
        }

        try thoughtRepo.markProcessed(thought)
        return createdIds
    }

    /// 将单个已解析任务保存到想法池或项目表
    func saveSingleParsedTask(_ parsed: ParsedTask, rawText: String) async throws -> UUID {
        let isProject = parsed.isProject ?? false
        if isProject {
            let project = try projectRepo.create(
                title: parsed.title,
                category: parsed.category,
                projectDecisionSource: parsed.isProject != nil ? "ai" : nil,
                deadline: parsed.deadline
            )
            return project.id
        } else {
            let idea = try ideaRepo.create(
                title: parsed.title,
                category: parsed.category,
                estimatedMinutes: parsed.estimatedMinutes,
                aiRecommended: parsed.recommended,
                recommendationReason: parsed.reason,
                note: parsed.note,
                deadline: parsed.deadline
            )
            return idea.id
        }
    }

    /// 提交自然语言 → AI 解析 → 进入想法池或项目表（一步到位）
    func submitThought(rawText: String) async throws -> [UUID] {
        let existingIdeas = try ideaRepo.fetchVisibleIdeas()
        let existingTitles = existingIdeas.map { $0.title }
        let parsedTasks = try await parseThoughts(rawText: rawText, existingTaskTitles: existingTitles)
        return try await saveParsedTasks(parsedTasks: parsedTasks, rawText: rawText)
    }

    /// 从想法池中挑选普通想法加入必做项
    func promoteToMustDo(
        ideaId: UUID,
        priority: TaskPriority? = nil,
        sortOrder: Int? = nil,
        estimatedMinutesOverride: Int? = nil
    ) async throws {
        guard let idea = try ideaRepo.fetchById(ideaId) else {
            throw NLPlanError.dataNotFound(entity: "Idea", id: ideaId)
        }
        guard idea.ideaStatus != .completed, idea.ideaStatus != .archived else { return }

        let estimatedMinutes = estimatedMinutesOverride ?? idea.estimatedMinutes
        guard estimatedMinutes != nil else {
            throw NLPlanError.invalidData(message: "普通想法缺少预估时长，无法加入必做项")
        }
        let activeLinkedTasks = try dailyTaskRepo.fetchActiveTasks(sourceIdeaId: idea.id)
        guard activeLinkedTasks.isEmpty else { return }

        _ = try dailyTaskRepo.create(
            title: idea.title,
            category: idea.category,
            estimatedMinutes: estimatedMinutes ?? 30,
            priority: priority ?? idea.taskPriority,
            aiRecommended: idea.aiRecommended,
            recommendationReason: idea.recommendationReason,
            sortOrder: sortOrder ?? idea.sortOrder,
            date: .now,
            sourceIdeaId: idea.id,
            sourceType: .idea
        )

        idea.ideaStatus = .inProgress
        try ideaRepo.update(idea)
    }

    /// 创建新的必做项（用于项目切片/推荐）
    func createMustDoTask(
        title: String,
        category: String,
        estimatedMinutes: Int,
        priority: TaskPriority = .medium,
        sortOrder: Int = 0,
        sourceIdeaId: UUID? = nil,
        sourceProjectId: UUID? = nil,
        arrangementId: UUID? = nil,
        recommendationReason: String? = nil
    ) async throws -> DailyTaskEntity {
        let sourceType: DailyTaskSourceType
        if sourceProjectId != nil {
            sourceType = .project
        } else if sourceIdeaId != nil {
            sourceType = .idea
        } else {
            sourceType = .none
        }

        let task = try dailyTaskRepo.create(
            title: title,
            category: category,
            estimatedMinutes: estimatedMinutes,
            priority: priority,
            aiRecommended: true,
            recommendationReason: recommendationReason,
            sortOrder: sortOrder,
            date: .now,
            sourceIdeaId: sourceIdeaId,
            sourceProjectId: sourceProjectId,
            arrangementId: arrangementId,
            sourceType: sourceType
        )

        if let sourceProjectId {
            try? await touchProjectRecommendationContext(projectId: sourceProjectId)
        } else if let sourceIdeaId, let idea = try ideaRepo.fetchById(sourceIdeaId) {
            idea.ideaStatus = .inProgress
            try ideaRepo.update(idea)
        }
        return task
    }

    /// 将必做项移回想法池
    func demoteToIdeaPool(taskId: UUID, markAttempted: Bool = false) async throws {
        guard let dailyTask = try dailyTaskRepo.fetchById(taskId) else {
            throw NLPlanError.dataNotFound(entity: "DailyTask", id: taskId)
        }

        if dailyTask.taskStatus == .running {
            try commitRunningTime(dailyTask)
        }

        if let arrangementId = dailyTask.arrangementId,
           let arrangement = try arrangementRepo.fetchById(arrangementId) {
            arrangement.status = ArrangementStatus.pending.rawValue
            try arrangementRepo.update(arrangement)
        }

        try dailyTaskRepo.deleteById(taskId)

        if let sourceIdeaId = dailyTask.sourceIdeaId,
           let sourceIdea = try ideaRepo.fetchById(sourceIdeaId) {
            sourceIdea.ideaStatus = markAttempted ? .attempted : .pending
            sourceIdea.attempted = markAttempted || sourceIdea.attempted
            try ideaRepo.update(sourceIdea)
        }
    }

    /// 删除想法池中的任务
    func deleteFromIdeaPool(ideaId: UUID) async throws {
        guard let idea = try ideaRepo.fetchById(ideaId) else {
            throw NLPlanError.dataNotFound(entity: "Idea", id: ideaId)
        }
        let linkedTasks = try dailyTaskRepo.fetchTasks(sourceIdeaId: ideaId)
        for task in linkedTasks {
            task.sourceIdeaId = nil
            task.sourceType = DailyTaskSourceType.none.rawValue
            try dailyTaskRepo.update(task)
        }
        try ideaRepo.delete(idea)
    }

    func toggleIdeaPin(ideaId: UUID) async throws {
        guard let idea = try ideaRepo.fetchById(ideaId) else {
            throw NLPlanError.dataNotFound(entity: "Idea", id: ideaId)
        }
        let pinned = !idea.isPinned
        idea.isPinned = pinned
        idea.pinnedAt = pinned ? .now : nil
        try ideaRepo.update(idea)
    }

    func toggleProjectPin(projectId: UUID) async throws {
        guard let project = try projectRepo.fetchById(projectId) else {
            throw NLPlanError.dataNotFound(entity: "Project", id: projectId)
        }
        let pinned = !project.isPinned
        project.isPinned = pinned
        project.pinnedAt = pinned ? .now : nil
        try projectRepo.update(project)
    }

    /// 删除项目
    func deleteProject(projectId: UUID) async throws {
        guard let project = try projectRepo.fetchById(projectId) else {
            throw NLPlanError.dataNotFound(entity: "Project", id: projectId)
        }
        let linkedTasks = try dailyTaskRepo.fetchTasks(sourceProjectId: projectId)
        for task in linkedTasks {
            task.sourceProjectId = nil
            task.arrangementId = nil
            task.sourceType = DailyTaskSourceType.none.rawValue
            try dailyTaskRepo.update(task)
        }
        try arrangementRepo.deleteByProject(projectId: projectId)
        try projectRepo.deleteProjectNotes(projectId: projectId)
        try projectRepo.delete(project)
    }

    // MARK: - 必做项操作

    /// 开始执行任务
    func startTask(taskId: UUID) async throws {
        guard let dailyTask = try dailyTaskRepo.fetchById(taskId) else {
            throw NLPlanError.dataNotFound(entity: "DailyTask", id: taskId)
        }
        guard dailyTask.taskStatus != .done else { return }

        let runningTasks = try dailyTaskRepo.fetchActiveRunningTasks()
        let toPause = await timerEngine.tasksToPauseBeforeStart(
            runningTaskIds: runningTasks.map { $0.id },
            newTaskId: taskId
        )
        for runningId in toPause {
            if let runningTask = try dailyTaskRepo.fetchById(runningId) {
                try pauseRunningTask(runningTask)
            }
        }

        dailyTask.timerAccumulatedSeconds = 0
        dailyTask.timerLastStartedAt = .now
        dailyTask.taskStatus = .running
        try dailyTaskRepo.update(dailyTask)

        _ = try sessionLogRepo.create(taskId: taskId, startedAt: .now, date: .now)
        touchSourceContext(dailyTask)
    }

    /// 暂停任务
    func pauseTask(taskId: UUID) async throws {
        guard let dailyTask = try dailyTaskRepo.fetchById(taskId) else {
            throw NLPlanError.dataNotFound(entity: "DailyTask", id: taskId)
        }
        guard dailyTask.taskStatus == .running else { return }
        try pauseRunningTask(dailyTask)
    }

    /// 恢复任务
    func resumeTask(taskId: UUID) async throws {
        guard let dailyTask = try dailyTaskRepo.fetchById(taskId) else {
            throw NLPlanError.dataNotFound(entity: "DailyTask", id: taskId)
        }
        guard dailyTask.taskStatus == .paused else { return }

        let runningTasks = try dailyTaskRepo.fetchActiveRunningTasks()
        let toPause = await timerEngine.tasksToPauseBeforeStart(
            runningTaskIds: runningTasks.map { $0.id },
            newTaskId: taskId
        )
        for runningId in toPause {
            if let runningTask = try dailyTaskRepo.fetchById(runningId) {
                try pauseRunningTask(runningTask)
            }
        }

        dailyTask.timerLastStartedAt = .now
        dailyTask.taskStatus = .running
        try dailyTaskRepo.update(dailyTask)

        _ = try sessionLogRepo.create(taskId: taskId, startedAt: .now, date: .now)
    }

    /// 标记任务完成
    func markComplete(taskId: UUID) async throws {
        guard let dailyTask = try dailyTaskRepo.fetchById(taskId) else {
            throw NLPlanError.dataNotFound(entity: "DailyTask", id: taskId)
        }

        if dailyTask.taskStatus == .running {
            try commitRunningTime(dailyTask)
            if let openLog = try sessionLogRepo.fetchOpenSession(taskId: taskId) {
                try sessionLogRepo.endSession(openLog)
            }
        }

        dailyTask.taskStatus = .done
        dailyTask.completedAt = .now
        try dailyTaskRepo.update(dailyTask)
        touchSourceContext(dailyTask)
    }

    // MARK: - 查询

    /// 获取所有想法池任务
    func fetchIdeaPool() async throws -> [IdeaEntity] {
        try ideaRepo.fetchVisibleIdeas()
    }

    // MARK: - 项目查询与更新

    func fetchProject(id: UUID) async throws -> ProjectEntity? {
        try projectRepo.fetchById(id)
    }

    func fetchVisibleProjects() async throws -> [ProjectEntity] {
        try projectRepo.fetchVisibleProjects()
    }

    func updateProject(_ project: ProjectEntity) async throws {
        try projectRepo.update(project)
    }

    func touchProjectRecommendationContext(projectId: UUID) async throws {
        guard let project = try projectRepo.fetchById(projectId) else {
            throw NLPlanError.dataNotFound(entity: "Project", id: projectId)
        }
        try projectRepo.touchRecommendationContext(project)
    }

    func updateProjectDescription(projectId: UUID, description: String?) async throws {
        guard let project = try projectRepo.fetchById(projectId) else {
            throw NLPlanError.dataNotFound(entity: "Project", id: projectId)
        }
        try projectRepo.updateDescription(project, description: description)
        try projectRepo.touchRecommendationContext(project)
    }

    func updatePlanningBackground(projectId: UUID, planningBackground: String?) async throws {
        guard let project = try projectRepo.fetchById(projectId) else {
            throw NLPlanError.dataNotFound(entity: "Project", id: projectId)
        }
        try projectRepo.updatePlanningBackground(project, planningBackground: planningBackground)
        try projectRepo.touchRecommendationContext(project)
    }

    func updateProjectTitle(projectId: UUID, title: String) async throws {
        guard let project = try projectRepo.fetchById(projectId) else {
            throw NLPlanError.dataNotFound(entity: "Project", id: projectId)
        }
        try projectRepo.updateTitle(project, title: title)
        try projectRepo.touchRecommendationContext(project)
    }

    // MARK: - 项目备注

    func addProjectNote(projectId: UUID, content: String) async throws {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = try projectRepo.createProjectNote(projectId: projectId, content: trimmed)
        try? await touchProjectRecommendationContext(projectId: projectId)
    }

    func fetchProjectNotesByProjectId(projectId: UUID) async throws -> [ProjectNoteEntity] {
        try projectRepo.fetchProjectNotes(projectId: projectId)
    }

    /// 编辑项目备注记录
    func updateProjectNote(noteId: UUID, content: String) async throws {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let note = try projectRepo.fetchProjectNoteById(noteId) else {
            throw NLPlanError.dataNotFound(entity: "ProjectNote", id: noteId)
        }
        try projectRepo.updateProjectNote(note, content: trimmed)
        try? await touchProjectRecommendationContext(projectId: note.projectId)
    }

    func generatePlanningBackgroundPrompt(projectId: UUID) async throws {
        guard let project = try projectRepo.fetchById(projectId) else { return }
        let activeTasks = try await fetchMustDo(sourceProjectId: projectId)
        let settledTasks = try await fetchSettledTasks(sourceProjectId: projectId)
        let notes = try await fetchProjectNotesByProjectId(projectId: projectId)

        let result = try await aiExecutionCoordinator.run {
            try await self.aiService.generatePlanningBackgroundPrompt(
                input: PlanningBackgroundPromptInput(
                    title: project.title,
                    category: project.category,
                    estimatedMinutes: nil,
                    attempted: false,
                    projectDescription: project.projectDescription,
                    planningBackground: project.planningBackground,
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

        try projectRepo.updatePlanningResearch(project, prompt: result.researchPrompt, reason: result.reason)
    }

    /// 获取想法池中的单个任务
    func fetchIdeaPoolTask(ideaId: UUID) async throws -> IdeaEntity? {
        try ideaRepo.fetchById(ideaId)
    }

    func fetchTaskSourceLookup(task: DailyTaskEntity) async -> DailyTaskSourceLookup {
        let hasIdeaSource = task.sourceIdeaId != nil
        let hasProjectSource = task.sourceProjectId != nil

        if hasIdeaSource && hasProjectSource {
            return .empty
        }

        if let sourceProjectId = task.sourceProjectId {
            return DailyTaskSourceLookup(
                idea: nil,
                project: (try? projectRepo.fetchById(sourceProjectId)) ?? nil
            )
        }

        if let sourceIdeaId = task.sourceIdeaId {
            return DailyTaskSourceLookup(
                idea: (try? ideaRepo.fetchById(sourceIdeaId)) ?? nil,
                project: nil
            )
        }

        return .empty
    }

    /// 更新想法实体
    func updateIdea(_ idea: IdeaEntity) async throws {
        try ideaRepo.update(idea)
    }

    /// 为项目生成推荐摘要
    func refreshProjectRecommendationSummary(projectId: UUID) async throws {
        guard let job = try await makeProjectRecommendationSummaryJob(projectId: projectId) else { return }
        let result = try await aiExecutionCoordinator.run {
            try await self.aiService.generateProjectRecommendationSummary(input: job.input)
        }
        _ = try await saveProjectRecommendationSummary(
            projectId: projectId,
            summary: result.summary,
            sourceUpdatedAt: job.contextUpdatedAt
        )
    }

    func makeProjectRecommendationSummaryJob(projectId: UUID) async throws -> ProjectRecommendationSummaryJob? {
        guard let project = try projectRepo.fetchById(projectId) else {
            throw NLPlanError.dataNotFound(entity: "Project", id: projectId)
        }

        let notes = try projectRepo.fetchProjectNotes(projectId: projectId)
        let activeTasks = try dailyTaskRepo.fetchTasks(sourceProjectId: projectId).filter { !$0.isSettled }
        let settledTasks = try dailyTaskRepo.fetchSettledTasks(sourceProjectId: projectId)
        let contextUpdatedAt = project.projectRecommendationContextUpdatedAt ?? project.updatedAt

        return ProjectRecommendationSummaryJob(
            ideaId: projectId,
            input: ProjectRecommendationSummaryInput(
                title: project.title,
                category: project.category,
                projectDescription: project.projectDescription,
                planningBackground: project.planningBackground,
                projectProgressSummary: project.projectProgressSummary,
                notes: notes.map(\.content),
                activeTasks: activeTasks.map { task in
                    let note = task.note?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let noteText = (note?.isEmpty == false) ? " - 备注：\(note!)" : ""
                    return "\(task.title) - \(task.taskStatus.displayName) - 预估\(task.estimatedMinutes)分钟\(noteText)"
                },
                settledTasks: settledTasks.map { task in
                    let reason = task.incompletionReason?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let reasonText = (reason?.isEmpty == false) ? " - 未完成原因：\(reason!)" : ""
                    return "\(task.title) - \(task.taskStatus == .done ? "已完成" : "未完成") - 实际\(task.actualMinutes ?? 0)分钟\(reasonText)"
                }
            ),
            contextUpdatedAt: contextUpdatedAt
        )
    }

    func saveProjectRecommendationSummary(
        projectId: UUID,
        summary: String,
        sourceUpdatedAt: Date
    ) async throws -> ProjectEntity? {
        guard let project = try projectRepo.fetchById(projectId) else {
            throw NLPlanError.dataNotFound(entity: "Project", id: projectId)
        }

        project.projectRecommendationSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        project.projectRecommendationSummaryGeneratedAt = .now
        project.projectRecommendationSummarySourceUpdatedAt = sourceUpdatedAt
        try projectRepo.update(project)
        return project
    }

    /// 获取指定日期的必做项
    func fetchMustDo(date: Date = .now) async throws -> [DailyTaskEntity] {
        try dailyTaskRepo.fetchTasks(date: date)
    }

    /// 获取绑定到指定来源的全部必做项
    func fetchMustDo(sourceIdeaId: UUID) async throws -> [DailyTaskEntity] {
        try dailyTaskRepo.fetchTasks(sourceIdeaId: sourceIdeaId)
    }

    /// 获取绑定到指定来源的已归档任务
    func fetchSettledTasks(sourceIdeaId: UUID) async throws -> [DailyTaskEntity] {
        try dailyTaskRepo.fetchSettledTasks(sourceIdeaId: sourceIdeaId)
    }

    /// 获取绑定到指定项目的全部必做项
    func fetchMustDo(sourceProjectId: UUID) async throws -> [DailyTaskEntity] {
        try dailyTaskRepo.fetchTasks(sourceProjectId: sourceProjectId)
    }

    /// 获取绑定到指定项目的已归档任务
    func fetchSettledTasks(sourceProjectId: UUID) async throws -> [DailyTaskEntity] {
        try dailyTaskRepo.fetchSettledTasks(sourceProjectId: sourceProjectId)
    }

    /// 获取活跃的正在运行的任务
    func fetchRunningTasks() async throws -> [DailyTaskEntity] {
        try dailyTaskRepo.fetchActiveRunningTasks()
    }

    /// 获取指定任务的总计时秒数
    func totalElapsedSeconds(taskId: UUID) async throws -> Int {
        guard let task = try dailyTaskRepo.fetchById(taskId) else { return 0 }
        return task.liveElapsedSeconds
    }

    /// 更新必做项实体
    func updateDailyTask(_ task: DailyTaskEntity) async throws {
        try dailyTaskRepo.update(task)
        if let sourceProjectId = task.sourceProjectId {
            try? await touchProjectRecommendationContext(projectId: sourceProjectId)
        }
    }

    func rebindTaskSource(taskId: UUID, sourceIdeaId: UUID?, sourceProjectId: UUID?) async throws {
        guard let task = try dailyTaskRepo.fetchById(taskId) else {
            throw NLPlanError.dataNotFound(entity: "DailyTask", id: taskId)
        }
        let previousSourceIdeaId = task.sourceIdeaId
        let previousSourceProjectId = task.sourceProjectId
        task.sourceIdeaId = sourceIdeaId
        task.sourceProjectId = sourceProjectId
        if sourceProjectId != nil {
            task.sourceIdeaId = nil
            task.sourceType = DailyTaskSourceType.project.rawValue
        } else if sourceIdeaId != nil {
            task.sourceProjectId = nil
            task.sourceType = DailyTaskSourceType.idea.rawValue
        } else {
            task.sourceType = DailyTaskSourceType.none.rawValue
        }
        try dailyTaskRepo.update(task)

        let affectedIdeaIds = Set([previousSourceIdeaId, sourceIdeaId].compactMap { $0 })
        for ideaId in affectedIdeaIds {
            if let idea = try ideaRepo.fetchById(ideaId) {
                try ideaRepo.update(idea)
            }
        }

        let affectedProjectIds = Set([previousSourceProjectId, task.sourceProjectId].compactMap { $0 })
        for projectId in affectedProjectIds {
            try? await touchProjectRecommendationContext(projectId: projectId)
        }
    }

    // MARK: - 项目安排

    func fetchArrangements(projectId: UUID) async throws -> [ProjectArrangementEntity] {
        try arrangementRepo.fetchByProject(projectId: projectId)
    }

    func fetchAllPendingArrangements() async throws -> [ProjectArrangementEntity] {
        try arrangementRepo.fetchAllPending()
    }

    func addArrangement(projectId: UUID, content: String, estimatedMinutes: Int, deadline: Date? = nil) async throws -> ProjectArrangementEntity {
        let order = try arrangementRepo.nextSortOrder(projectId: projectId)
        return try arrangementRepo.create(
            projectId: projectId,
            content: content,
            estimatedMinutes: estimatedMinutes,
            deadline: deadline,
            sortOrder: order
        )
    }

    func updateArrangement(_ item: ProjectArrangementEntity, content: String? = nil, estimatedMinutes: Int? = nil, deadline: Date? = nil) async throws {
        if let content { item.content = content }
        if let estimatedMinutes { item.estimatedMinutes = estimatedMinutes }
        if let deadline { item.deadline = deadline }
        try arrangementRepo.update(item)
    }

    func updateArrangementStatus(_ item: ProjectArrangementEntity, status: ArrangementStatus) async throws {
        item.status = status.rawValue
        try arrangementRepo.update(item)
    }

    func deleteArrangement(_ item: ProjectArrangementEntity) async throws {
        try arrangementRepo.delete(item)
    }

    func fetchArrangement(_ id: UUID) async throws -> ProjectArrangementEntity? {
        try arrangementRepo.fetchById(id)
    }

    func promoteArrangementToMustDo(
        arrangementId: UUID,
        priority: TaskPriority? = nil,
        sortOrder: Int? = nil,
        estimatedMinutesOverride: Int? = nil,
        titleOverride: String? = nil,
        categoryOverride: String? = nil,
        aiRecommended: Bool = false,
        recommendationReason: String? = nil
    ) async throws -> DailyTaskEntity? {
        guard let arrangement = try arrangementRepo.fetchById(arrangementId) else {
            throw NLPlanError.dataNotFound(entity: "ProjectArrangement", id: arrangementId)
        }
        guard arrangement.arrangementStatus != .done else { return nil }

        let projectEntity = try projectRepo.fetchById(arrangement.projectId)
        let category = categoryOverride ?? projectEntity?.category ?? ""
        let projectId = arrangement.projectId

        if let existingTask = try dailyTaskRepo.fetchActiveTask(arrangementId: arrangementId) {
            if arrangement.arrangementStatus != .inProgress {
                arrangement.status = ArrangementStatus.inProgress.rawValue
                try arrangementRepo.update(arrangement)
            }
            return existingTask
        }

        let task = try dailyTaskRepo.create(
            title: titleOverride ?? formattedArrangementTitle(arrangement.content, projectTitle: projectEntity?.title),
            category: category,
            estimatedMinutes: estimatedMinutesOverride ?? arrangement.estimatedMinutes,
            priority: priority ?? .medium,
            aiRecommended: aiRecommended,
            recommendationReason: recommendationReason,
            sortOrder: sortOrder ?? arrangement.sortOrder,
            date: .now,
            note: nil,
            sourceProjectId: projectId,
            arrangementId: arrangement.id,
            sourceType: .project
        )

        arrangement.status = ArrangementStatus.inProgress.rawValue
        try arrangementRepo.update(arrangement)

        if let projectEntity {
            try projectRepo.touchRecommendationContext(projectEntity)
        }

        return task
    }

    private func formattedArrangementTitle(_ content: String, projectTitle: String?) -> String {
        let prefix = projectTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "项目"
        return "\(prefix): \(content)"
    }

    func fetchPendingArrangements(projectId: UUID) async throws -> [ProjectArrangementEntity] {
        try arrangementRepo.fetchPendingByProject(projectId: projectId)
    }

    func hasPendingArrangements(projectId: UUID) async throws -> Bool {
        !(try arrangementRepo.fetchPendingByProject(projectId: projectId)).isEmpty
    }

    private func dailyTaskSourceType(sourceIdeaId: UUID?) throws -> DailyTaskSourceType {
        guard let sourceIdeaId else { return .none }
        if try projectRepo.fetchById(sourceIdeaId) != nil { return .project }
        if try ideaRepo.fetchById(sourceIdeaId) != nil { return .idea }
        return .none
    }

    // MARK: - Timer Helpers

    private func commitRunningTime(_ task: DailyTaskEntity) throws {
        if let lastStarted = task.timerLastStartedAt {
            task.timerAccumulatedSeconds += Int(Date.now.timeIntervalSince(lastStarted))
        }
        task.timerLastStartedAt = nil
    }

    private func pauseRunningTask(_ task: DailyTaskEntity) throws {
        try commitRunningTime(task)
        task.taskStatus = .paused
        try dailyTaskRepo.update(task)
        if let openLog = try sessionLogRepo.fetchOpenSession(taskId: task.id) {
            try sessionLogRepo.endSession(openLog)
        }
        touchSourceContext(task)
    }

    private func touchSourceContext(_ task: DailyTaskEntity) {
        if let sourceProjectId = task.sourceProjectId,
           let project = try? projectRepo.fetchById(sourceProjectId) {
            try? projectRepo.touchRecommendationContext(project)
        }
    }

    // MARK: - Checkpoint & Recovery

    func checkpointRunningTasks() async throws {
        let runningTasks = try dailyTaskRepo.fetchActiveRunningTasks()
        for task in runningTasks {
            try commitRunningTime(task)
            task.timerLastStartedAt = .now
            try dailyTaskRepo.update(task)
        }
    }

    func recoverRunningTasksOnStartup() async throws {
        let runningTasks = try dailyTaskRepo.fetchActiveRunningTasks()
        for task in runningTasks {
            task.timerLastStartedAt = nil
            task.taskStatus = .paused
            try dailyTaskRepo.update(task)

            if let openLog = try sessionLogRepo.fetchOpenSession(taskId: task.id) {
                try sessionLogRepo.endSession(openLog, endedAt: openLog.startedAt.addingTimeInterval(TimeInterval(task.timerAccumulatedSeconds)))
            }
        }
    }

    func stopAllRunningTasks() async throws {
        let runningTasks = try dailyTaskRepo.fetchActiveRunningTasks()
        for task in runningTasks {
            try pauseRunningTask(task)
        }
    }
}
