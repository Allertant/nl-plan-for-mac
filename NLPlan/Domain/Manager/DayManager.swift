import Foundation
import SwiftData

/// 每日管理器 — 管理"一天"的生命周期，触发日终评分，处理跨天逻辑
@MainActor
final class DayManager {

    private let taskRepo: TaskRepository
    private let ideaRepo: IdeaRepository
    private let dailyTaskRepo: DailyTaskRepository
    private let summaryRepo: SummaryRepository
    private let sessionLogRepo: SessionLogRepository
    private let timerEngine: TimerEngine
    private let aiService: AIServiceProtocol

    init(
        taskRepo: TaskRepository,
        ideaRepo: IdeaRepository,
        dailyTaskRepo: DailyTaskRepository,
        summaryRepo: SummaryRepository,
        sessionLogRepo: SessionLogRepository,
        timerEngine: TimerEngine,
        aiService: AIServiceProtocol
    ) {
        self.taskRepo = taskRepo
        self.ideaRepo = ideaRepo
        self.dailyTaskRepo = dailyTaskRepo
        self.summaryRepo = summaryRepo
        self.sessionLogRepo = sessionLogRepo
        self.timerEngine = timerEngine
        self.aiService = aiService
    }

    // MARK: - End Day

    /// 结束今天：先评分（不修改任何状态）→ 成功后再停止任务并保存
    func endDay() async throws -> DailySummaryEntity {
        let today = Calendar.current.startOfDay(for: .now)
        return try await settleDay(date: today)
    }

    /// 结算指定日期。今天结算成功后会停止当前运行任务；历史日期只结算对应日期数据。
    func settleDay(date: Date, incompleteNotes: [UUID: String] = [:]) async throws -> DailySummaryEntity {
        let settlementDate = Calendar.current.startOfDay(for: date)
        let isToday = Calendar.current.isDateInToday(settlementDate)

        // 1. 先评分（可安全取消，不修改任何数据）
        let mustDoTasks = try taskRepo.fetchTasks(date: settlementDate, pool: .mustDo)
        let grade = try await gradeWithFallback(tasks: mustDoTasks, incompleteNotes: incompleteNotes)

        // 2. 今日评分成功后，停止所有运行中任务
        if isToday {
            let stoppedTasks = await timerEngine.stopAll()
            for stopInfo in stoppedTasks {
                if let openLog = try sessionLogRepo.fetchOpenSession(taskId: stopInfo.taskId) {
                    try sessionLogRepo.endSession(openLog)
                }
                if let task = try taskRepo.fetchById(stopInfo.taskId) {
                    try taskRepo.updateStatus(task, status: .pending)
                }
            }
        }

        // 3. 保存评分
        let summary = try summaryRepo.create(
            date: settlementDate,
            grade: grade.grade,
            summary: grade.summary,
            suggestion: grade.suggestion,
            totalPlannedMinutes: grade.stats.totalPlannedMinutes,
            totalActualMinutes: grade.stats.totalActualMinutes,
            completedCount: grade.stats.completedTasks,
            totalCount: grade.stats.totalTasks,
            gradingBasis: grade.gradingBasis
        )
        try archiveAndClearSettledTasks(
            tasks: mustDoTasks,
            settlementDate: settlementDate,
            incompleteNotes: incompleteNotes
        )
        return summary
    }

    /// 检查是否存在需要用户手动补结算的日期。只返回提醒日期，不自动评分或迁移。
    func pendingSettlementDate(referenceDate: Date = .now) throws -> Date? {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: referenceDate)!
        let yesterdayStart = Calendar.current.startOfDay(for: yesterday)
        if try summaryRepo.fetch(date: yesterdayStart) != nil {
            return nil
        }
        let yesterdayTasks = try taskRepo.fetchTasks(date: yesterdayStart, pool: .mustDo)
        return yesterdayTasks.isEmpty ? nil : yesterdayStart
    }

    // MARK: - Check Yesterday

    /// 检查是否需要触发昨日的自动评分
    func checkAndGradeYesterday() async throws -> DailySummaryEntity? {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        let yesterdayStart = Calendar.current.startOfDay(for: yesterday)

        // 检查昨天是否已有评分
        if try summaryRepo.fetch(date: yesterdayStart) != nil {
            return nil
        }

        // 检查昨天是否有必做项
        let yesterdayTasks = try taskRepo.fetchTasks(date: yesterdayStart, pool: .mustDo)
        if yesterdayTasks.isEmpty {
            return nil
        }

        // 先迁移未完成的任务，然后评分
        _ = try taskRepo.migrateUnfinishedMustDo(date: yesterdayStart)

        let grade = try await gradeWithFallback(tasks: yesterdayTasks, fallbackSummary: "自动补评（AI 不可用）")
        return try summaryRepo.create(
            date: yesterdayStart,
            grade: grade.grade,
            summary: grade.summary,
            suggestion: grade.suggestion,
            totalPlannedMinutes: grade.stats.totalPlannedMinutes,
            totalActualMinutes: grade.stats.totalActualMinutes,
            completedCount: grade.stats.completedTasks,
            totalCount: grade.stats.totalTasks,
            gradingBasis: grade.gradingBasis
        )
    }

    // MARK: - Migrate

    /// 跨天迁移：将昨日未完成的必做项移回想法池
    func migrateUnfinishedMustDo() async throws -> [TaskEntity] {
        let today = Calendar.current.startOfDay(for: .now)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        return try taskRepo.migrateUnfinishedMustDo(date: yesterday)
    }

    // MARK: - Appeal

    /// 驳斥评分
    func appealGrade(
        date: Date,
        userFeedback: String
    ) async throws -> DailySummaryEntity {
        guard let summary = try summaryRepo.fetch(date: date) else {
            throw NLPlanError.dataNotFound(entity: "DailySummary", id: UUID())
        }
        guard summary.appealCount < 3 else {
            throw NLPlanError.appealLimitExceeded
        }

        let tasks = try taskRepo.fetchTasks(date: date, pool: .mustDo)
        let stats = computeStats(tasks: tasks)
        let originalInput = try buildSummaryInput(tasks: tasks, stats: stats)
        let originalGrade = DailyGrade(
            grade: summary.gradeEnum,
            summary: summary.summary,
            stats: GradeStats(
                totalTasks: summary.totalCount,
                completedTasks: summary.completedCount,
                totalPlannedMinutes: summary.totalPlannedMinutes,
                totalActualMinutes: summary.totalActualMinutes,
                deviationRate: stats.deviationRate,
                extraCompleted: stats.extraCompleted
            ),
            suggestion: summary.suggestion ?? "",
            gradingBasis: summary.gradingBasis ?? ""
        )

        let newGrade = try await aiService.appealGrade(
            originalGrade: originalGrade,
            originalInput: originalInput,
            userFeedback: userFeedback
        )

        summary.grade = newGrade.grade.rawValue
        summary.summary = newGrade.summary
        summary.suggestion = newGrade.suggestion
        summary.gradingBasis = newGrade.gradingBasis
        summary.appealCount += 1
        try summaryRepo.update(summary)

        return summary
    }

    // MARK: - Undo

    /// 撤销今日评分
    func undoTodaySummary() throws {
        let today = Calendar.current.startOfDay(for: .now)
        guard let summary = try summaryRepo.fetch(date: today) else { return }
        try summaryRepo.delete(summary)
    }

    // MARK: - Query

    /// 获取今日统计
    func todayStats() async throws -> DayStats {
        let today = Calendar.current.startOfDay(for: .now)
        let tasks = try taskRepo.fetchTasks(date: today, pool: .mustDo)
        return computeStats(tasks: tasks)
    }

    /// 获取今日评分
    func fetchTodaySummary() async throws -> DailySummaryEntity? {
        let today = Calendar.current.startOfDay(for: .now)
        return try summaryRepo.fetch(date: today)
    }

    /// 获取指定日期评分
    func fetchSummary(date: Date) async throws -> DailySummaryEntity? {
        try summaryRepo.fetch(date: Calendar.current.startOfDay(for: date))
    }

    /// 获取指定日期必做项
    func fetchMustDoTasks(date: Date) async throws -> [TaskEntity] {
        try taskRepo.fetchTasks(date: Calendar.current.startOfDay(for: date), pool: .mustDo)
    }

    /// 获取历史评分
    func fetchHistory(from: Date, to: Date) async throws -> [DailySummaryEntity] {
        try summaryRepo.fetchRange(from: from, to: to)
    }

    // MARK: - Private

    /// 从任务列表构建 AI 评分输入
    private func buildSummaryInput(
        tasks: [TaskEntity],
        stats: DayStats,
        incompleteNotes: [UUID: String] = [:]
    ) throws -> DailySummaryInput {
        DailySummaryInput(
            settlementDate: Date.now.dateString,
            totalTasks: stats.totalTasks,
            completedTasks: stats.completedTasks,
            totalPlannedMinutes: stats.totalPlannedMinutes,
            totalActualMinutes: stats.totalActualMinutes,
            deviationRate: stats.deviationRate,
            extraCompleted: stats.extraCompleted,
            taskDetails: try tasks.map { task in
                TaskDetail(
                    title: task.title,
                    estimatedMinutes: task.estimatedMinutes,
                    actualMinutes: max(0, task.totalElapsedSeconds / 60),
                    completed: task.status == TaskStatus.done.rawValue,
                    priority: task.priority,
                    sourceType: try summarySourceType(for: task),
                    note: summaryNote(for: task, incompleteNotes: incompleteNotes)
                )
            }
        )
    }

    /// AI 评分（带降级方案）
    private func gradeWithFallback(
        tasks: [TaskEntity],
        fallbackSummary: String = "AI 评分不可用，使用基础评分。",
        incompleteNotes: [UUID: String] = [:]
    ) async throws -> DailyGrade {
        let stats = computeStats(tasks: tasks)
        let input = try buildSummaryInput(tasks: tasks, stats: stats, incompleteNotes: incompleteNotes)

        do {
            return try await aiService.generateDailyGrade(summaryInput: input)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return DailyGrade(
                grade: stats.fallbackGrade,
                summary: "\(fallbackSummary)完成率：\(String(format: "%.0f%%", stats.completionRate * 100))",
                stats: GradeStats(
                    totalTasks: stats.totalTasks,
                    completedTasks: stats.completedTasks,
                    totalPlannedMinutes: stats.totalPlannedMinutes,
                    totalActualMinutes: stats.totalActualMinutes,
                    deviationRate: stats.deviationRate,
                    extraCompleted: stats.extraCompleted
                ),
                suggestion: "明天继续加油！",
                gradingBasis: "基于规则的降级评分（AI 不可用）"
            )
        }
    }

    private func computeStats(tasks: [TaskEntity]) -> DayStats {
        let totalTasks = tasks.count
        let completedTasks = tasks.filter { $0.status == TaskStatus.done.rawValue }.count
        let totalPlannedMinutes = tasks.reduce(0) { $0 + $1.estimatedMinutes }
        let totalActualSeconds = tasks.reduce(0) { $0 + $1.totalElapsedSeconds }
        let totalActualMinutes = totalActualSeconds / 60

        let deviationRate: Double
        if totalPlannedMinutes > 0 {
            deviationRate = abs(Double(totalActualMinutes - totalPlannedMinutes)) / Double(totalPlannedMinutes)
        } else {
            deviationRate = 0
        }

        return DayStats(
            totalTasks: totalTasks,
            completedTasks: completedTasks,
            totalPlannedMinutes: totalPlannedMinutes,
            totalActualMinutes: totalActualMinutes,
            deviationRate: deviationRate,
            extraCompleted: 0  // TODO: 计算额外完成的想法池任务
        )
    }

    private func summarySourceType(for task: TaskEntity) throws -> String {
        guard let sourceIdeaId = task.sourceIdeaId else {
            return task.aiRecommended ? "无来源必做项" : "普通想法来源必做项"
        }
        guard let source = try taskRepo.fetchById(sourceIdeaId) else {
            return "普通想法来源必做项"
        }
        return source.isProjectTask ? "项目链接必做项" : "普通想法来源必做项"
    }

    private func summaryNote(for task: TaskEntity, incompleteNotes: [UUID: String]) -> String? {
        var parts: [String] = []
        if let note = task.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            parts.append(note)
        }
        if let note = incompleteNotes[task.id]?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            parts.append(note)
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n结算备注：")
    }

    private func archiveAndClearSettledTasks(
        tasks: [TaskEntity],
        settlementDate: Date,
        incompleteNotes: [UUID: String]
    ) throws {
        var affectedProjectIdeaIds: Set<UUID> = []

        for task in tasks {
            let sourceType = try summarySourceType(for: task)
            let note = summaryNote(for: task, incompleteNotes: incompleteNotes)
            try taskRepo.createSettlementRecord(
                task: task,
                settlementDate: settlementDate,
                actualMinutes: max(0, task.totalElapsedSeconds / 60),
                sourceType: sourceType,
                note: note
            )
            try archiveSplitDailyTask(task, note: note)

            if sourceType == "普通想法来源必做项", let sourceIdeaId = task.sourceIdeaId, let sourceIdea = try taskRepo.fetchById(sourceIdeaId) {
                if task.status == TaskStatus.done.rawValue {
                    sourceIdea.status = TaskStatus.done.rawValue
                    try updateSplitIdea(
                        sourceIdeaId: sourceIdeaId,
                        status: .completed,
                        attempted: sourceIdea.attempted,
                        logType: .completed,
                        logContent: "完成必做项：\(task.title)",
                        relatedTaskId: task.id,
                        settlementDate: settlementDate
                    )
                } else {
                    sourceIdea.status = IdeaStatus.attempted.rawValue
                    sourceIdea.attempted = true
                    if let note, !note.isEmpty {
                        let timestamp = Date.now.dateString
                        let existingNote = sourceIdea.note?.trimmingCharacters(in: .whitespacesAndNewlines)
                        let appendedNote = "\(timestamp)\n\(note)"
                        sourceIdea.note = [existingNote, appendedNote]
                            .compactMap { value in
                                guard let value, !value.isEmpty else { return nil }
                                return value
                            }
                            .joined(separator: "\n\n")
                    }
                    try updateSplitIdea(
                        sourceIdeaId: sourceIdeaId,
                        status: .attempted,
                        attempted: true,
                        logType: .attempted,
                        logContent: settlementLogContent(task: task, note: note),
                        relatedTaskId: task.id,
                        settlementDate: settlementDate
                    )
                }
                taskRepo.deleteWithoutSaving(task)
            } else if sourceType == "项目链接必做项", let sourceIdeaId = task.sourceIdeaId {
                affectedProjectIdeaIds.insert(sourceIdeaId)
                try appendProjectSettlementNoteIfNeeded(
                    sourceIdeaId: sourceIdeaId,
                    task: task,
                    note: note,
                    settlementDate: settlementDate
                )
                taskRepo.deleteWithoutSaving(task)
            } else if task.status != TaskStatus.done.rawValue && sourceType == "普通想法来源必做项" {
                task.pool = TaskPool.ideaPool.rawValue
                task.status = TaskStatus.pending.rawValue
                task.date = Date.now
                task.attempted = true
            } else {
                taskRepo.deleteWithoutSaving(task)
            }
        }
        try taskRepo.save()
        try refreshProjectIdeaStatusesAfterSettlement(affectedProjectIdeaIds)
    }

    private func archiveSplitDailyTask(_ task: TaskEntity, note: String?) throws {
        guard let dailyTask = try dailyTaskRepo.fetchByMigratedTaskId(task.id) else { return }
        dailyTask.settlementNote = note
        dailyTask.status = task.status
        try dailyTaskRepo.update(dailyTask)
        try dailyTaskRepo.delete(dailyTask)
    }

    private func updateSplitIdea(
        sourceIdeaId: UUID,
        status: IdeaStatus,
        attempted: Bool,
        logType: IdeaLogType,
        logContent: String,
        relatedTaskId: UUID,
        settlementDate: Date
    ) throws {
        guard let idea = try ideaRepo.fetchById(sourceIdeaId) else { return }
        idea.ideaStatus = status
        idea.attempted = attempted
        try ideaRepo.update(idea)
        _ = try ideaRepo.addLog(
            ideaId: sourceIdeaId,
            type: logType,
            content: logContent,
            relatedTaskId: relatedTaskId,
            settlementDate: settlementDate
        )
    }

    private func settlementLogContent(task: TaskEntity, note: String?) -> String {
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedNote, !trimmedNote.isEmpty else {
            return "未完成必做项：\(task.title)"
        }
        return "未完成必做项：\(task.title)\n\(trimmedNote)"
    }

    private func appendProjectSettlementNoteIfNeeded(
        sourceIdeaId: UUID,
        task: TaskEntity,
        note: String?,
        settlementDate: Date
    ) throws {
        guard task.status != TaskStatus.done.rawValue else { return }
        guard let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmedNote.isEmpty else {
            return
        }
        guard let projectIdea = try taskRepo.fetchById(sourceIdeaId) else { return }

        let content = """
        \(settlementDate.shortDateTimeString)
        必做项：\(task.title)
        备注：\(trimmedNote)
        """
        _ = try taskRepo.createProjectNote(task: projectIdea, content: content)
    }

    private func refreshProjectIdeaStatusesAfterSettlement(_ ideaIds: Set<UUID>) throws {
        for ideaId in ideaIds {
            let activeTasks = try taskRepo.fetchTasks(sourceIdeaId: ideaId)
                .filter { $0.status != TaskStatus.done.rawValue }
            guard activeTasks.isEmpty else { continue }

            if let sourceIdea = try taskRepo.fetchById(ideaId),
               sourceIdea.status == IdeaStatus.inProgress.rawValue {
                sourceIdea.status = TaskStatus.pending.rawValue
                try taskRepo.update(sourceIdea)
            }

            if let idea = try ideaRepo.fetchById(ideaId),
               idea.ideaStatus == .inProgress {
                idea.ideaStatus = .pending
                try ideaRepo.update(idea)
            }
        }
    }
}
