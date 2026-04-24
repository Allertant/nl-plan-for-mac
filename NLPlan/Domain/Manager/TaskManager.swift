import Foundation
import SwiftData

/// 任务生命周期管理
@MainActor
final class TaskManager {

    private let ideaRepo: IdeaRepository
    private let dailyTaskRepo: DailyTaskRepository
    private let thoughtRepo: ThoughtRepository
    private let sessionLogRepo: SessionLogRepository
    private let aiService: AIServiceProtocol
    private let timerEngine: TimerEngine

    init(
        ideaRepo: IdeaRepository,
        dailyTaskRepo: DailyTaskRepository,
        thoughtRepo: ThoughtRepository,
        sessionLogRepo: SessionLogRepository,
        aiService: AIServiceProtocol,
        timerEngine: TimerEngine
    ) {
        self.ideaRepo = ideaRepo
        self.dailyTaskRepo = dailyTaskRepo
        self.thoughtRepo = thoughtRepo
        self.sessionLogRepo = sessionLogRepo
        self.aiService = aiService
        self.timerEngine = timerEngine
    }

    // MARK: - 想法池操作

    /// 仅调用 AI 解析，不保存（供确认流程使用）
    func parseThoughts(rawText: String, existingTaskTitles: [String]) async throws -> [ParsedTask] {
        try await aiService.parseThoughts(
            input: rawText,
            existingTaskTitles: existingTaskTitles
        )
    }

    /// 根据用户指令修改已解析的任务（供确认流程使用）
    func refineParsedTasks(
        originalInput: String,
        currentTasks: [ParsedTask],
        userInstruction: String
    ) async throws -> [ParsedTask] {
        try await aiService.refineTasks(
            originalInput: originalInput,
            currentTasks: currentTasks,
            userInstruction: userInstruction
        )
    }

    /// 判断解析结果中的任务是否属于项目型想法
    func classifyProjects(tasks: [ProjectClassificationInput]) async throws -> [ProjectClassification] {
        try await aiService.classifyProjects(tasks: tasks)
    }

    /// 将已解析的任务保存到想法池
    func saveParsedTasks(parsedTasks: [ParsedTask], rawText: String) async throws -> [IdeaEntity] {
        // 1. 保存原始想法
        let thought = try thoughtRepo.create(rawText: rawText)

        // 2. 转为 IdeaEntity 并保存
        var createdIdeas: [IdeaEntity] = []
        for (index, parsed) in parsedTasks.enumerated() {
            let isProject = parsed.isProject ?? false
            let idea = try ideaRepo.create(
                title: parsed.title,
                category: parsed.category,
                estimatedMinutes: isProject ? nil : parsed.estimatedMinutes,
                aiRecommended: parsed.recommended,
                recommendationReason: parsed.reason,
                sortOrder: index,
                isProject: isProject,
                projectDecisionSource: parsed.isProject != nil ? "ai" : nil,
                projectProgress: isProject ? 0 : nil
            )
            createdIdeas.append(idea)
        }

        // 3. 标记想法已处理
        try thoughtRepo.markProcessed(thought)

        return createdIdeas
    }

    /// 提交自然语言 → AI 解析 → 进入想法池（一步到位）
    func submitThought(rawText: String) async throws -> [IdeaEntity] {
        let existingIdeas = try ideaRepo.fetchVisibleIdeas()
        let existingTitles = existingIdeas.map { $0.title }
        let parsedTasks = try await parseThoughts(rawText: rawText, existingTaskTitles: existingTitles)
        return try await saveParsedTasks(parsedTasks: parsedTasks, rawText: rawText)
    }

    /// 从想法池中挑选任务加入必做项
    func promoteToMustDo(ideaId: UUID, priority: TaskPriority? = nil, sortOrder: Int? = nil) async throws {
        guard let idea = try ideaRepo.fetchById(ideaId) else {
            throw NLPlanError.dataNotFound(entity: "Idea", id: ideaId)
        }
        guard idea.ideaStatus != .completed, idea.ideaStatus != .archived else { return }

        if !idea.isProject {
            guard idea.estimatedMinutes != nil else {
                throw NLPlanError.invalidData(message: "普通想法缺少预估时长，无法加入必做项")
            }
            let activeLinkedTasks = try dailyTaskRepo.fetchActiveTasks(sourceIdeaId: idea.id)
            guard activeLinkedTasks.isEmpty else { return }
        }

        _ = try dailyTaskRepo.create(
            title: idea.title,
            category: idea.category,
            estimatedMinutes: idea.estimatedMinutes ?? 30,
            priority: priority ?? idea.taskPriority,
            aiRecommended: idea.aiRecommended,
            recommendationReason: idea.recommendationReason,
            sortOrder: sortOrder ?? idea.sortOrder,
            date: .now,
            sourceIdeaId: idea.id,
            sourceType: idea.isProject ? .project : .idea
        )

        if idea.isProject {
            try ideaRepo.touchProjectRecommendationContext(idea)
        }
        idea.ideaStatus = .inProgress
        try ideaRepo.update(idea)
    }

    /// 创建新的必做项（用于项目切片）
    func createMustDoTask(
        title: String,
        category: String,
        estimatedMinutes: Int,
        priority: TaskPriority = .medium,
        sortOrder: Int = 0,
        sourceIdeaId: UUID? = nil,
        recommendationReason: String? = nil
    ) async throws -> DailyTaskEntity {
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
            sourceType: try dailyTaskSourceType(sourceIdeaId: sourceIdeaId)
        )

        if let sourceIdeaId, let idea = try ideaRepo.fetchById(sourceIdeaId), !idea.isProject {
            idea.ideaStatus = .inProgress
            try ideaRepo.update(idea)
        } else if let sourceIdeaId, let idea = try ideaRepo.fetchById(sourceIdeaId), idea.isProject {
            try ideaRepo.touchProjectRecommendationContext(idea)
        }
        return task
    }

    /// 将必做项移回想法池
    func demoteToIdeaPool(taskId: UUID, markAttempted: Bool = false) async throws {
        guard let dailyTask = try dailyTaskRepo.fetchById(taskId) else {
            throw NLPlanError.dataNotFound(entity: "DailyTask", id: taskId)
        }

        // 停止计时（如果正在运行）
        if dailyTask.taskStatus == .running {
            _ = await timerEngine.stopTask(taskId)
            if let openLog = try sessionLogRepo.fetchOpenSession(taskId: taskId) {
                try sessionLogRepo.endSession(openLog)
            }
        }

        try dailyTaskRepo.deleteById(taskId)

        if let sourceIdeaId = dailyTask.sourceIdeaId,
           let sourceIdea = try ideaRepo.fetchById(sourceIdeaId) {
            sourceIdea.ideaStatus = markAttempted ? .attempted : .pending
            sourceIdea.attempted = markAttempted || sourceIdea.attempted
            try ideaRepo.update(sourceIdea)
            try ideaRepo.touchProjectRecommendationContext(sourceIdea)
        }
    }

    /// 删除想法池中的任务
    func deleteFromIdeaPool(ideaId: UUID) async throws {
        guard let idea = try ideaRepo.fetchById(ideaId) else {
            throw NLPlanError.dataNotFound(entity: "Idea", id: ideaId)
        }
        try ideaRepo.delete(idea)
    }

    /// 为项目想法添加备注记录
    func addProjectNote(ideaId: UUID, content: String) async throws {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let idea = try ideaRepo.fetchById(ideaId) else {
            throw NLPlanError.dataNotFound(entity: "Idea", id: ideaId)
        }
        guard idea.isProject else { return }
        _ = try ideaRepo.createProjectNote(ideaId: idea.id, content: trimmed)
        try ideaRepo.touchProjectRecommendationContext(idea)
    }

    /// 编辑项目备注记录
    func updateProjectNote(noteId: UUID, content: String) async throws {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let note = try ideaRepo.fetchProjectNoteById(noteId) else {
            throw NLPlanError.dataNotFound(entity: "ProjectNote", id: noteId)
        }
        try ideaRepo.updateProjectNote(note, content: trimmed)
        if let ideaId = note.ideaId, let idea = try ideaRepo.fetchById(ideaId) {
            try ideaRepo.touchProjectRecommendationContext(idea)
        }
    }

    // MARK: - 必做项操作

    /// 开始执行任务
    func startTask(taskId: UUID) async throws {
        guard let dailyTask = try dailyTaskRepo.fetchById(taskId) else {
            throw NLPlanError.dataNotFound(entity: "DailyTask", id: taskId)
        }
        guard dailyTask.taskStatus != .done else { return }

        // 1. TimerEngine 处理切换逻辑
        let stoppedTasks = await timerEngine.startTask(taskId)

        // 2. 持久化被停止任务的 session
        for stopInfo in stoppedTasks {
            if let openLog = try sessionLogRepo.fetchOpenSession(taskId: stopInfo.taskId) {
                try sessionLogRepo.endSession(openLog)
            }
            if let stoppedTask = try dailyTaskRepo.fetchById(stopInfo.taskId) {
                stoppedTask.taskStatus = .pending
                try dailyTaskRepo.update(stoppedTask)
            }
        }

        // 3. 为新任务创建 open session
        _ = try sessionLogRepo.create(taskId: taskId, startedAt: .now, date: .now)

        // 4. 更新任务状态
        dailyTask.taskStatus = .running
        try dailyTaskRepo.update(dailyTask)
    }

    /// 标记任务完成
    func markComplete(taskId: UUID) async throws {
        guard let dailyTask = try dailyTaskRepo.fetchById(taskId) else {
            throw NLPlanError.dataNotFound(entity: "DailyTask", id: taskId)
        }

        // 停止计时
        if dailyTask.taskStatus == .running {
            _ = await timerEngine.stopTask(taskId)
            if let openLog = try sessionLogRepo.fetchOpenSession(taskId: taskId) {
                try sessionLogRepo.endSession(openLog)
            }
        }

        dailyTask.taskStatus = .done
        try dailyTaskRepo.update(dailyTask)
        if let sourceIdeaId = dailyTask.sourceIdeaId,
           let sourceIdea = try ideaRepo.fetchById(sourceIdeaId) {
            try ideaRepo.touchProjectRecommendationContext(sourceIdea)
        }
    }

    // MARK: - 查询

    /// 获取所有想法池任务
    func fetchIdeaPool() async throws -> [IdeaEntity] {
        try ideaRepo.fetchVisibleIdeas()
    }

    /// 获取想法池中的单个任务
    func fetchIdeaPoolTask(ideaId: UUID) async throws -> IdeaEntity? {
        try ideaRepo.fetchById(ideaId)
    }

    /// 更新想法实体
    func updateIdea(_ idea: IdeaEntity) async throws {
        try ideaRepo.update(idea)
    }

    /// 为单个项目生成推荐阶段使用的状态摘要，并写回项目
    func refreshProjectRecommendationSummary(ideaId: UUID) async throws {
        guard let job = try await makeProjectRecommendationSummaryJob(ideaId: ideaId) else { return }
        let result = try await aiService.generateProjectRecommendationSummary(input: job.input)
        _ = try await saveProjectRecommendationSummary(
            ideaId: ideaId,
            summary: result.summary,
            sourceUpdatedAt: job.contextUpdatedAt
        )
    }

    func makeProjectRecommendationSummaryJob(ideaId: UUID) async throws -> ProjectRecommendationSummaryJob? {
        guard let idea = try ideaRepo.fetchById(ideaId) else {
            throw NLPlanError.dataNotFound(entity: "Idea", id: ideaId)
        }
        guard idea.isProject else { return nil }

        let notes = try ideaRepo.fetchProjectNotes(ideaId: ideaId)
        let activeTasks = try dailyTaskRepo.fetchTasks(sourceIdeaId: ideaId).filter { !$0.isSettled }
        let settledTasks = try dailyTaskRepo.fetchSettledTasks(sourceIdeaId: ideaId)
        let contextUpdatedAt = idea.projectRecommendationContextUpdatedAt ?? idea.updatedAt

        return ProjectRecommendationSummaryJob(
            ideaId: ideaId,
            input: ProjectRecommendationSummaryInput(
                title: idea.title,
                category: idea.category,
                projectDescription: idea.projectDescription,
                planningBackground: idea.planningBackground,
                projectProgressSummary: idea.projectProgressSummary,
                notes: notes.map(\.content),
                activeTasks: activeTasks.map { task in
                    let note = task.note?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let noteText = (note?.isEmpty == false) ? " - 备注：\(note!)" : ""
                    return "\(task.title) - \(task.taskStatus.displayName) - 预估\(task.estimatedMinutes)分钟\(noteText)"
                },
                settledTasks: settledTasks.map { task in
                    let note = task.settlementNote?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let noteText = (note?.isEmpty == false) ? " - 备注：\(note!)" : ""
                    return "\(task.title) - \(task.taskStatus == .done ? "已完成" : "未完成") - 实际\(task.actualMinutes ?? 0)分钟\(noteText)"
                }
            ),
            contextUpdatedAt: contextUpdatedAt
        )
    }

    func saveProjectRecommendationSummary(
        ideaId: UUID,
        summary: String,
        sourceUpdatedAt: Date
    ) async throws -> IdeaEntity? {
        guard let idea = try ideaRepo.fetchById(ideaId) else {
            throw NLPlanError.dataNotFound(entity: "Idea", id: ideaId)
        }
        guard idea.isProject else { return nil }

        idea.projectRecommendationSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        idea.projectRecommendationSummaryGeneratedAt = .now
        idea.projectRecommendationSummarySourceUpdatedAt = sourceUpdatedAt
        try ideaRepo.update(idea)
        return idea
    }

    /// 获取指定日期的必做项
    func fetchMustDo(date: Date = .now) async throws -> [DailyTaskEntity] {
        try dailyTaskRepo.fetchTasks(date: date)
    }

    /// 获取绑定到指定项目想法的全部必做项
    func fetchMustDo(sourceIdeaId: UUID) async throws -> [DailyTaskEntity] {
        try dailyTaskRepo.fetchTasks(sourceIdeaId: sourceIdeaId)
    }

    /// 获取绑定到指定项目想法的已归档任务
    func fetchSettledTasks(sourceIdeaId: UUID) async throws -> [DailyTaskEntity] {
        try dailyTaskRepo.fetchSettledTasks(sourceIdeaId: sourceIdeaId)
    }

    /// 获取活跃的正在运行的任务
    func fetchRunningTasks() async throws -> [DailyTaskEntity] {
        try dailyTaskRepo.fetchActiveRunningTasks()
    }

    /// 获取指定任务的总计时秒数
    func totalElapsedSeconds(taskId: UUID) async throws -> Int {
        try sessionLogRepo.totalElapsedSeconds(taskId: taskId)
    }

    /// 更新必做项实体
    func updateDailyTask(_ task: DailyTaskEntity) async throws {
        try dailyTaskRepo.update(task)
        if let sourceIdeaId = task.sourceIdeaId,
           let sourceIdea = try ideaRepo.fetchById(sourceIdeaId) {
            try ideaRepo.touchProjectRecommendationContext(sourceIdea)
        }
    }

    func rebindTaskSource(taskId: UUID, sourceIdeaId: UUID?) async throws {
        guard let task = try dailyTaskRepo.fetchById(taskId) else {
            throw NLPlanError.dataNotFound(entity: "DailyTask", id: taskId)
        }
        let previousSourceIdeaId = task.sourceIdeaId
        task.sourceIdeaId = sourceIdeaId
        task.sourceType = try dailyTaskSourceType(sourceIdeaId: sourceIdeaId).rawValue
        try dailyTaskRepo.update(task)

        let affectedIdeaIds = Set([previousSourceIdeaId, sourceIdeaId].compactMap { $0 })
        for ideaId in affectedIdeaIds {
            if let idea = try ideaRepo.fetchById(ideaId) {
                try ideaRepo.touchProjectRecommendationContext(idea)
            }
        }
    }

    func touchProjectRecommendationContext(ideaId: UUID) async throws {
        guard let idea = try ideaRepo.fetchById(ideaId) else {
            throw NLPlanError.dataNotFound(entity: "Idea", id: ideaId)
        }
        try ideaRepo.touchProjectRecommendationContext(idea)
    }

    /// 获取项目备注列表
    func fetchProjectNotes(ideaId: UUID) async throws -> [ProjectNoteEntity] {
        try ideaRepo.fetchProjectNotes(ideaId: ideaId)
    }

    private func dailyTaskSourceType(sourceIdeaId: UUID?) throws -> DailyTaskSourceType {
        guard let sourceIdeaId else { return .none }
        guard let idea = try ideaRepo.fetchById(sourceIdeaId) else { return .idea }
        return idea.isProject ? .project : .idea
    }
}
