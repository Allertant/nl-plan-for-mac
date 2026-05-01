import Foundation
import SwiftData

/// 每日管理器 — 管理"一天"的生命周期，触发日终评分，处理跨天逻辑
@MainActor
final class DayManager {

    private let ideaRepo: IdeaRepository
    private let dailyTaskRepo: DailyTaskRepository
    private let summaryRepo: SummaryRepository
    private let sessionLogRepo: SessionLogRepository
    private let arrangementRepo: ProjectArrangementRepository
    private let timerEngine: TimerEngine
    private let aiService: AIServiceProtocol
    private let aiExecutionCoordinator = AIExecutionCoordinator()

    init(
        ideaRepo: IdeaRepository,
        dailyTaskRepo: DailyTaskRepository,
        summaryRepo: SummaryRepository,
        sessionLogRepo: SessionLogRepository,
        arrangementRepo: ProjectArrangementRepository,
        timerEngine: TimerEngine,
        aiService: AIServiceProtocol
    ) {
        self.ideaRepo = ideaRepo
        self.dailyTaskRepo = dailyTaskRepo
        self.summaryRepo = summaryRepo
        self.sessionLogRepo = sessionLogRepo
        self.arrangementRepo = arrangementRepo
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
        let mustDoTasks = try dailyTaskRepo.fetchTasks(date: settlementDate)
        let grade = try await gradeWithFallback(tasks: mustDoTasks, incompleteNotes: incompleteNotes)

        // 2. 今日评分成功后，暂停所有运行中任务
        if isToday {
            let runningTasks = try dailyTaskRepo.fetchActiveRunningTasks()
            for task in runningTasks {
                if let lastStarted = task.timerLastStartedAt {
                    task.timerAccumulatedSeconds += Int(Date.now.timeIntervalSince(lastStarted))
                }
                task.timerLastStartedAt = nil
                task.taskStatus = .pending
                try dailyTaskRepo.update(task)
                if let openLog = try sessionLogRepo.fetchOpenSession(taskId: task.id) {
                    try sessionLogRepo.endSession(openLog)
                }
                if let sourceIdeaId = task.sourceIdeaId,
                   let sourceIdea = try ideaRepo.fetchById(sourceIdeaId) {
                    try ideaRepo.touchProjectRecommendationContext(sourceIdea)
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

    /// 检查是否存在需要用户手动补结算的日期。从昨天往前扫描，找到最近一个有必做项但没 summary 的日期。
    func pendingSettlementDate(referenceDate: Date = .now) throws -> Date? {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: referenceDate)
        for offset in 1...30 {
            guard let date = cal.date(byAdding: .day, value: -offset, to: todayStart) else { break }
            let dayStart = cal.startOfDay(for: date)
            if try summaryRepo.fetch(date: dayStart) != nil {
                continue
            }
            let tasks = try dailyTaskRepo.fetchTasks(date: dayStart)
            if !tasks.isEmpty {
                return dayStart
            }
        }
        return nil
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
        let yesterdayTasks = try dailyTaskRepo.fetchTasks(date: yesterdayStart)
        if yesterdayTasks.isEmpty {
            return nil
        }

        // 先迁移未完成的任务，然后评分
        _ = try dailyTaskRepo.migrateUnfinishedMustDo(date: yesterdayStart)

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
    func migrateUnfinishedMustDo() async throws -> [DailyTaskEntity] {
        let today = Calendar.current.startOfDay(for: .now)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        return try dailyTaskRepo.migrateUnfinishedMustDo(date: yesterday)
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

        let tasks = try dailyTaskRepo.fetchTasks(date: date)
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

        let newGrade = try await aiExecutionCoordinator.run {
            try await self.aiService.appealGrade(
                originalGrade: originalGrade,
                originalInput: originalInput,
                userFeedback: userFeedback
            )
        }

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
        let tasks = try dailyTaskRepo.fetchTasks(date: today)
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
    func fetchMustDoTasks(date: Date) async throws -> [DailyTaskEntity] {
        try dailyTaskRepo.fetchTasks(date: date)
    }

    /// 获取历史评分
    func fetchHistory(from: Date, to: Date) async throws -> [DailySummaryEntity] {
        try summaryRepo.fetchRange(from: from, to: to)
    }

    // MARK: - Private

    /// 从任务列表构建 AI 评分输入
    private func buildSummaryInput(
        tasks: [DailyTaskEntity],
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
                    actualMinutes: max(0, try sessionLogRepo.totalElapsedSeconds(taskId: task.id) / 60),
                    completed: task.taskStatus == .done,
                    priority: task.priority,
                    sourceType: summarySourceType(for: task),
                    note: combinedNote(for: task, incompleteNotes: incompleteNotes)
                )
            }
        )
    }

    /// AI 评分（带降级方案）
    private func gradeWithFallback(
        tasks: [DailyTaskEntity],
        fallbackSummary: String = "AI 评分不可用，使用基础评分。",
        incompleteNotes: [UUID: String] = [:]
    ) async throws -> DailyGrade {
        let stats = computeStats(tasks: tasks)
        let input = try buildSummaryInput(tasks: tasks, stats: stats, incompleteNotes: incompleteNotes)

        do {
            return try await aiExecutionCoordinator.run {
                try await self.aiService.generateDailyGrade(summaryInput: input)
            }
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

    private func computeStats(tasks: [DailyTaskEntity]) -> DayStats {
        let totalTasks = tasks.count
        let completedTasks = tasks.filter { $0.taskStatus == .done }.count
        let totalPlannedMinutes = tasks.reduce(0) { $0 + $1.estimatedMinutes }
        let totalActualSeconds = tasks.reduce(0) { total, task in
            let secs = (try? sessionLogRepo.totalElapsedSeconds(taskId: task.id)) ?? 0
            return total + secs
        }
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
            extraCompleted: 0
        )
    }

    private func summarySourceType(for task: DailyTaskEntity) -> String {
        guard let sourceIdeaId = task.sourceIdeaId else {
            return task.aiRecommended ? "无来源必做项" : "普通想法来源必做项"
        }
        guard let source = try? ideaRepo.fetchById(sourceIdeaId) else {
            return "普通想法来源必做项"
        }
        return source.isProject ? "项目链接必做项" : "普通想法来源必做项"
    }

    private func summaryNote(for task: DailyTaskEntity, incompleteNotes: [UUID: String]) -> String? {
        let note = incompleteNotes[task.id]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let note, !note.isEmpty else { return nil }
        return note
    }

    private func combinedNote(for task: DailyTaskEntity, incompleteNotes: [UUID: String]) -> String? {
        var parts: [String] = []
        if let note = task.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            parts.append(note)
        }
        if let note = incompleteNotes[task.id]?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            parts.append(note)
        }
        return parts.isEmpty ? nil : parts.joined(separator: "；")
    }

    private func archiveAndClearSettledTasks(
        tasks: [DailyTaskEntity],
        settlementDate: Date,
        incompleteNotes: [UUID: String]
    ) throws {
        var affectedProjectIdeaIds: Set<UUID> = []

        for task in tasks {
            let sourceType = summarySourceType(for: task)
            let note = summaryNote(for: task, incompleteNotes: incompleteNotes)
            let actualMinutes = max(0, try sessionLogRepo.totalElapsedSeconds(taskId: task.id) / 60)

            task.isSettled = true
            task.settledAt = settlementDate
            task.actualMinutes = actualMinutes
            task.incompletionReason = note
            try dailyTaskRepo.update(task)

            // 更新关联安排状态为 done
            if let arrangementId = task.arrangementId,
               let arrangement = try arrangementRepo.fetchById(arrangementId) {
                arrangement.status = ArrangementStatus.done.rawValue
                try arrangementRepo.update(arrangement)
            }

            if let sourceIdeaId = task.sourceIdeaId, let sourceIdea = try ideaRepo.fetchById(sourceIdeaId) {
                if sourceIdea.isProject {
                    try ideaRepo.touchProjectRecommendationContext(sourceIdea)
                } else {
                    if task.taskStatus == .done {
                        sourceIdea.ideaStatus = .completed
                    } else {
                        sourceIdea.ideaStatus = .attempted
                        sourceIdea.attempted = true
                    }
                    try ideaRepo.update(sourceIdea)
                    try ideaRepo.touchProjectRecommendationContext(sourceIdea)
                }

                if sourceType == "项目链接必做项" {
                    affectedProjectIdeaIds.insert(sourceIdeaId)
                }
            }
        }
        try refreshProjectIdeaStatusesAfterSettlement(affectedProjectIdeaIds)
    }

    private func refreshProjectIdeaStatusesAfterSettlement(_ ideaIds: Set<UUID>) throws {
        for ideaId in ideaIds {
            let activeTasks = try dailyTaskRepo.fetchActiveTasks(sourceIdeaId: ideaId)
            guard activeTasks.isEmpty else { continue }

            if let idea = try ideaRepo.fetchById(ideaId),
               idea.ideaStatus == .inProgress {
                idea.ideaStatus = .pending
                try ideaRepo.update(idea)
                try ideaRepo.touchProjectRecommendationContext(idea)
            }
        }
    }
}
