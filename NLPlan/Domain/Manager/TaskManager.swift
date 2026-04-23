import Foundation
import SwiftData

/// 任务生命周期管理
@MainActor
final class TaskManager {

    private let taskRepo: TaskRepository
    private let ideaRepo: IdeaRepository
    private let dailyTaskRepo: DailyTaskRepository
    private let thoughtRepo: ThoughtRepository
    private let sessionLogRepo: SessionLogRepository
    private let aiService: AIServiceProtocol
    private let timerEngine: TimerEngine

    init(
        taskRepo: TaskRepository,
        ideaRepo: IdeaRepository,
        dailyTaskRepo: DailyTaskRepository,
        thoughtRepo: ThoughtRepository,
        sessionLogRepo: SessionLogRepository,
        aiService: AIServiceProtocol,
        timerEngine: TimerEngine
    ) {
        self.taskRepo = taskRepo
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

    /// 将已解析的任务保存到想法池（供确认流程使用）
    func saveParsedTasks(parsedTasks: [ParsedTask], rawText: String) async throws -> [TaskEntity] {
        // 1. 保存原始想法
        let thought = try thoughtRepo.create(rawText: rawText)

        // 2. 转为 TaskEntity 并保存
        var createdTasks: [TaskEntity] = []
        for (index, parsed) in parsedTasks.enumerated() {
            let task = try taskRepo.create(
                title: parsed.title,
                category: parsed.category,
                estimatedMinutes: parsed.estimatedMinutes,
                aiRecommended: parsed.recommended,
                recommendationReason: parsed.reason,
                pool: .ideaPool,
                date: .now
            )
            task.sortOrder = index
            if let isProject = parsed.isProject {
                task.isProject = isProject
                task.projectDecisionSource = "ai"
                task.projectProgress = 0
                task.projectProgressSummary = nil
                task.projectProgressUpdatedAt = nil
            }
            try taskRepo.update(task)
            _ = try ideaRepo.create(
                id: task.id,
                title: task.title,
                category: task.category,
                estimatedMinutes: task.estimatedMinutes,
                priority: task.taskPriority,
                aiRecommended: task.aiRecommended,
                recommendationReason: task.recommendationReason,
                sortOrder: task.sortOrder,
                status: .pending,
                attempted: task.attempted,
                note: task.note,
                isProject: task.isProjectTask,
                projectDecisionSource: task.projectDecisionSource,
                projectProgress: task.projectProgress,
                projectProgressSummary: task.projectProgressSummary,
                projectProgressUpdatedAt: task.projectProgressUpdatedAt,
                createdDate: task.createdDate,
                migratedFromTaskId: task.id
            )
            createdTasks.append(task)
        }

        // 3. 标记想法已处理
        try thoughtRepo.markProcessed(thought)

        return createdTasks
    }

    /// 提交自然语言 → AI 解析 → 进入想法池（一步到位）
    func submitThought(rawText: String) async throws -> [TaskEntity] {
        let existingTasks = try taskRepo.fetchAllIdeaPoolTasks()
        let existingTitles = existingTasks.map { $0.title }
        let parsedTasks = try await parseThoughts(rawText: rawText, existingTaskTitles: existingTitles)
        return try await saveParsedTasks(parsedTasks: parsedTasks, rawText: rawText)
    }

    /// 从想法池中挑选任务加入必做项
    func promoteToMustDo(taskId: UUID, priority: TaskPriority? = nil, sortOrder: Int? = nil) async throws {
        guard let task = try taskRepo.fetchById(taskId) else {
            throw NLPlanError.dataNotFound(entity: "Task", id: taskId)
        }
        guard task.pool == TaskPool.ideaPool.rawValue else {
            throw NLPlanError.taskNotInExpectedPool(expected: .ideaPool, actual: task.taskPool)
        }
        if let priority { task.taskPriority = priority }
        if let sortOrder { task.sortOrder = sortOrder }
        try taskRepo.moveToMustDo(task)
        if let idea = try ideaRepo.fetchById(task.id) {
            idea.ideaStatus = .inProgress
            try ideaRepo.update(idea)
        }
        _ = try dailyTaskRepo.create(
            id: task.id,
            title: task.title,
            category: task.category,
            estimatedMinutes: task.estimatedMinutes,
            priority: task.taskPriority,
            aiRecommended: task.aiRecommended,
            recommendationReason: task.recommendationReason,
            sortOrder: task.sortOrder,
            date: task.date,
            createdDate: task.createdDate,
            attempted: task.attempted,
            note: task.note,
            sourceIdeaId: task.id,
            sourceType: task.isProjectTask ? .project : .idea,
            migratedFromTaskId: task.id
        )
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
    ) async throws -> TaskEntity {
        let task = try taskRepo.create(
            title: title,
            category: category,
            estimatedMinutes: estimatedMinutes,
            priority: priority,
            aiRecommended: true,
            recommendationReason: recommendationReason,
            pool: .mustDo,
            date: .now,
            sourceIdeaId: sourceIdeaId
        )
        task.sortOrder = sortOrder
        try taskRepo.update(task)
        _ = try dailyTaskRepo.create(
            id: task.id,
            title: task.title,
            category: task.category,
            estimatedMinutes: task.estimatedMinutes,
            priority: task.taskPriority,
            aiRecommended: task.aiRecommended,
            recommendationReason: task.recommendationReason,
            sortOrder: task.sortOrder,
            date: task.date,
            createdDate: task.createdDate,
            sourceIdeaId: sourceIdeaId,
            sourceType: try dailyTaskSourceType(sourceIdeaId: sourceIdeaId),
            migratedFromTaskId: task.id
        )
        if let sourceIdeaId, let idea = try ideaRepo.fetchById(sourceIdeaId), !idea.isProject {
            idea.ideaStatus = .inProgress
            try ideaRepo.update(idea)
        }
        return task
    }

    /// 将必做项移回想法池
    func demoteToIdeaPool(taskId: UUID, markAttempted: Bool = false) async throws {
        guard let task = try taskRepo.fetchById(taskId) else {
            throw NLPlanError.dataNotFound(entity: "Task", id: taskId)
        }
        guard task.pool == TaskPool.mustDo.rawValue else {
            throw NLPlanError.taskNotInExpectedPool(expected: .mustDo, actual: task.taskPool)
        }

        // 停止计时（如果正在运行）
        if task.status == TaskStatus.running.rawValue {
            _ = await timerEngine.stopTask(taskId)
            if let openLog = try sessionLogRepo.fetchOpenSession(taskId: taskId) {
                try sessionLogRepo.endSession(openLog)
            }
        }

        try taskRepo.moveToIdeaPool(task, markAttempted: markAttempted)
        try dailyTaskRepo.deleteByMigratedTaskId(task.id)
        if let idea = try ideaRepo.fetchById(task.id) {
            idea.ideaStatus = markAttempted ? .attempted : .pending
            idea.attempted = markAttempted || idea.attempted
            try ideaRepo.update(idea)
        }
    }

    /// 删除想法池中的任务
    func deleteFromIdeaPool(taskId: UUID) async throws {
        guard let task = try taskRepo.fetchById(taskId) else {
            throw NLPlanError.dataNotFound(entity: "Task", id: taskId)
        }
        guard task.pool == TaskPool.ideaPool.rawValue else {
            throw NLPlanError.taskNotInExpectedPool(expected: .ideaPool, actual: task.taskPool)
        }
        if let idea = try ideaRepo.fetchById(task.id) {
            try ideaRepo.delete(idea)
        }
        try taskRepo.delete(task)
    }

    /// 为项目想法添加备注记录
    func addProjectNote(taskId: UUID, content: String) async throws {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let task = try taskRepo.fetchById(taskId) else {
            throw NLPlanError.dataNotFound(entity: "Task", id: taskId)
        }
        guard task.isProjectTask else { return }
        _ = try taskRepo.createProjectNote(task: task, content: trimmed)
    }

    /// 编辑项目备注记录
    func updateProjectNote(noteId: UUID, content: String) async throws {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let note = try taskRepo.fetchProjectNoteById(noteId) else {
            throw NLPlanError.dataNotFound(entity: "ProjectNote", id: noteId)
        }
        try taskRepo.updateProjectNote(note, content: trimmed)
    }

    // MARK: - 必做项操作

    /// 开始执行任务
    func startTask(taskId: UUID) async throws {
        guard let task = try taskRepo.fetchById(taskId) else {
            throw NLPlanError.dataNotFound(entity: "Task", id: taskId)
        }
        guard task.pool == TaskPool.mustDo.rawValue else {
            throw NLPlanError.taskNotInExpectedPool(expected: .mustDo, actual: task.taskPool)
        }
        guard task.status != TaskStatus.done.rawValue else { return }

        // 1. TimerEngine 处理切换逻辑
        let stoppedTasks = await timerEngine.startTask(taskId)

        // 2. 持久化被停止任务的 session（查找并结束已有的 open session）
        for stopInfo in stoppedTasks {
            if let openLog = try sessionLogRepo.fetchOpenSession(taskId: stopInfo.taskId) {
                try sessionLogRepo.endSession(openLog)
            }
            if let stoppedTask = try taskRepo.fetchById(stopInfo.taskId) {
                try taskRepo.updateStatus(stoppedTask, status: .pending)
            }
        }

        // 3. 为新任务创建 open session
        _ = try sessionLogRepo.create(taskId: taskId, startedAt: .now, date: .now)

        // 4. 更新任务状态
        try taskRepo.updateStatus(task, status: .running)
    }

    /// 标记任务完成
    func markComplete(taskId: UUID) async throws {
        guard let task = try taskRepo.fetchById(taskId) else {
            throw NLPlanError.dataNotFound(entity: "Task", id: taskId)
        }

        // 停止计时
        if task.status == TaskStatus.running.rawValue {
            _ = await timerEngine.stopTask(taskId)
            // 结束已有的 open session
            if let openLog = try sessionLogRepo.fetchOpenSession(taskId: taskId) {
                try sessionLogRepo.endSession(openLog)
            }
        }

        try taskRepo.markComplete(task)
        if let dailyTask = try dailyTaskRepo.fetchByMigratedTaskId(task.id) {
            dailyTask.taskStatus = .done
            try dailyTaskRepo.update(dailyTask)
        }
    }

    // MARK: - 查询

    /// 获取所有想法池任务
    func fetchIdeaPool() async throws -> [TaskEntity] {
        try taskRepo.fetchAllIdeaPoolTasks()
    }

    /// 获取想法池中的单个任务
    func fetchIdeaPoolTask(taskId: UUID) async throws -> TaskEntity? {
        try taskRepo.fetchById(taskId)
    }

    /// 更新任务（直接保存已有实体的修改）
    func updateTask(_ task: TaskEntity) async throws {
        try taskRepo.update(task)
        try syncSplitTables(from: task)
    }

    /// 获取指定日期的必做项
    func fetchMustDo(date: Date = .now) async throws -> [TaskEntity] {
        try taskRepo.fetchTasks(date: date, pool: .mustDo)
    }

    /// 获取绑定到指定项目想法的全部必做项
    func fetchMustDo(sourceIdeaId: UUID) async throws -> [TaskEntity] {
        try taskRepo.fetchTasks(sourceIdeaId: sourceIdeaId)
    }

    /// 获取绑定到指定项目想法的归档记录
    func fetchSettlementRecords(sourceIdeaId: UUID) async throws -> [TaskSettlementRecordEntity] {
        try taskRepo.fetchSettlementRecords(sourceIdeaId: sourceIdeaId)
    }

    /// 获取活跃的正在运行的任务
    func fetchRunningTasks() async throws -> [TaskEntity] {
        try taskRepo.fetchActiveRunningTasks()
    }

    /// 保存任务的排序顺序（拖拽排序后调用）
    func saveTaskOrders() async throws {
        let tasks = try taskRepo.fetchTasks(date: .now, pool: .mustDo)
        if let anyTask = tasks.first {
            try taskRepo.update(anyTask)
        }
    }

    private func dailyTaskSourceType(sourceIdeaId: UUID?) throws -> DailyTaskSourceType {
        guard let sourceIdeaId else { return .none }
        guard let idea = try ideaRepo.fetchById(sourceIdeaId) else { return .idea }
        return idea.isProject ? .project : .idea
    }

    private func syncSplitTables(from task: TaskEntity) throws {
        if task.pool == TaskPool.ideaPool.rawValue, let idea = try ideaRepo.fetchById(task.id) {
            idea.title = task.title
            idea.category = task.category
            idea.estimatedMinutes = task.estimatedMinutes
            idea.priority = task.priority
            idea.aiRecommended = task.aiRecommended
            idea.recommendationReason = task.recommendationReason
            idea.sortOrder = task.sortOrder
            idea.attempted = task.attempted
            idea.note = task.note
            idea.isProject = task.isProjectTask
            idea.projectDecisionSource = task.projectDecisionSource
            idea.projectProgress = task.projectProgress
            idea.projectProgressSummary = task.projectProgressSummary
            idea.projectProgressUpdatedAt = task.projectProgressUpdatedAt
            try ideaRepo.update(idea)
        }

        if task.pool == TaskPool.mustDo.rawValue, let dailyTask = try dailyTaskRepo.fetchByMigratedTaskId(task.id) {
            dailyTask.title = task.title
            dailyTask.category = task.category
            dailyTask.estimatedMinutes = task.estimatedMinutes
            dailyTask.priority = task.priority
            dailyTask.aiRecommended = task.aiRecommended
            dailyTask.recommendationReason = task.recommendationReason
            dailyTask.sortOrder = task.sortOrder
            dailyTask.status = task.status
            dailyTask.date = task.date
            dailyTask.attempted = task.attempted
            dailyTask.note = task.note
            dailyTask.sourceIdeaId = task.sourceIdeaId
            dailyTask.sourceType = try dailyTaskSourceType(sourceIdeaId: task.sourceIdeaId).rawValue
            try dailyTaskRepo.update(dailyTask)
        }
    }
}
