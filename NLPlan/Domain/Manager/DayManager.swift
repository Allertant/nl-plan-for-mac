import Foundation
import SwiftData

/// 每日管理器 — 管理"一天"的生命周期，触发日终评分，处理跨天逻辑
actor DayManager {

    private let taskRepo: TaskRepository
    private let summaryRepo: SummaryRepository
    private let sessionLogRepo: SessionLogRepository
    private let timerEngine: TimerEngine
    private let aiService: AIServiceProtocol

    init(
        taskRepo: TaskRepository,
        summaryRepo: SummaryRepository,
        sessionLogRepo: SessionLogRepository,
        timerEngine: TimerEngine,
        aiService: AIServiceProtocol
    ) {
        self.taskRepo = taskRepo
        self.summaryRepo = summaryRepo
        self.sessionLogRepo = sessionLogRepo
        self.timerEngine = timerEngine
        self.aiService = aiService
    }

    // MARK: - End Day

    /// 结束今天：停止所有任务 → 生成统计 → 调用 AI 评分
    func endDay() async throws -> DailySummaryEntity {
        let today = Calendar.current.startOfDay(for: .now)

        // 1. 停止所有运行中任务
        let stoppedTasks = await timerEngine.stopAll()
        for stopInfo in stoppedTasks {
            if let openLog = try sessionLogRepo.fetchOpenSession(taskId: stopInfo.taskId) {
                try sessionLogRepo.endSession(openLog)
            }

            if let task = try taskRepo.fetchById(stopInfo.taskId) {
                try taskRepo.updateStatus(task, status: .pending)
            }
        }

        // 2. 汇总今日统计
        let mustDoTasks = try taskRepo.fetchTasks(date: today, pool: .mustDo)
        let stats = computeStats(tasks: mustDoTasks)

        // 3. 构造 AI 输入
        let summaryInput = DailySummaryInput(
            totalTasks: stats.totalTasks,
            completedTasks: stats.completedTasks,
            totalPlannedMinutes: stats.totalPlannedMinutes,
            totalActualMinutes: stats.totalActualMinutes,
            deviationRate: stats.deviationRate,
            extraCompleted: stats.extraCompleted,
            taskDetails: mustDoTasks.map { task in
                TaskDetail(
                    title: task.title,
                    estimatedMinutes: task.estimatedMinutes,
                    actualMinutes: max(0, task.totalElapsedSeconds / 60),
                    completed: task.status == TaskStatus.done.rawValue
                )
            }
        )

        // 4. 调用 AI 评分（带降级方案）
        let grade: DailyGrade
        do {
            grade = try await aiService.generateDailyGrade(summaryInput: summaryInput)
        } catch {
            // 降级：使用基于规则的基础评分
            let fallbackGrade = stats.fallbackGrade
            grade = DailyGrade(
                grade: fallbackGrade,
                summary: "AI 评分不可用，使用基础评分。完成率：\(String(format: "%.0f%%", stats.completionRate * 100))",
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

        // 5. 保存评分结果
        let summary = try summaryRepo.create(
            date: today,
            grade: grade.grade,
            summary: grade.summary,
            suggestion: grade.suggestion,
            totalPlannedMinutes: grade.stats.totalPlannedMinutes,
            totalActualMinutes: grade.stats.totalActualMinutes,
            completedCount: grade.stats.completedTasks,
            totalCount: grade.stats.totalTasks,
            gradingBasis: grade.gradingBasis
        )

        return summary
    }

    // MARK: - Check Yesterday

    /// 检查是否需要触发昨日的自动评分
    func checkAndGradeYesterday() async throws -> DailySummaryEntity? {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        let yesterdayStart = Calendar.current.startOfDay(for: yesterday)

        // 检查昨天是否已有评分
        if try summaryRepo.fetch(date: yesterdayStart) != nil {
            return nil // 已评分
        }

        // 检查昨天是否有必做项
        let yesterdayTasks = try taskRepo.fetchTasks(date: yesterdayStart, pool: .mustDo)
        if yesterdayTasks.isEmpty {
            return nil // 没有任务，无需评分
        }

        // 执行评分
        // 先迁移未完成的任务
        _ = try taskRepo.migrateUnfinishedMustDo(date: yesterdayStart)

        // 然后评分
        let stats = computeStats(tasks: yesterdayTasks)
        let summaryInput = DailySummaryInput(
            totalTasks: stats.totalTasks,
            completedTasks: stats.completedTasks,
            totalPlannedMinutes: stats.totalPlannedMinutes,
            totalActualMinutes: stats.totalActualMinutes,
            deviationRate: stats.deviationRate,
            extraCompleted: stats.extraCompleted,
            taskDetails: yesterdayTasks.map { task in
                TaskDetail(
                    title: task.title,
                    estimatedMinutes: task.estimatedMinutes,
                    actualMinutes: max(0, task.totalElapsedSeconds / 60),
                    completed: task.status == TaskStatus.done.rawValue
                )
            }
        )

        let grade: DailyGrade
        do {
            grade = try await aiService.generateDailyGrade(summaryInput: summaryInput)
        } catch {
            let fallbackGrade = stats.fallbackGrade
            grade = DailyGrade(
                grade: fallbackGrade,
                summary: "自动补评（AI 不可用）。完成率：\(String(format: "%.0f%%", stats.completionRate * 100))",
                stats: GradeStats(
                    totalTasks: stats.totalTasks,
                    completedTasks: stats.completedTasks,
                    totalPlannedMinutes: stats.totalPlannedMinutes,
                    totalActualMinutes: stats.totalActualMinutes,
                    deviationRate: stats.deviationRate,
                    extraCompleted: stats.extraCompleted
                ),
                suggestion: "",
                gradingBasis: "基于规则的降级评分（AI 不可用）"
            )
        }

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

        // 检查申诉次数
        guard summary.appealCount < 3 else {
            throw NLPlanError.appealLimitExceeded
        }

        // 获取原始任务数据
        let tasks = try taskRepo.fetchTasks(date: date, pool: .mustDo)
        let stats = computeStats(tasks: tasks)

        let originalInput = DailySummaryInput(
            totalTasks: stats.totalTasks,
            completedTasks: stats.completedTasks,
            totalPlannedMinutes: stats.totalPlannedMinutes,
            totalActualMinutes: stats.totalActualMinutes,
            deviationRate: stats.deviationRate,
            extraCompleted: stats.extraCompleted,
            taskDetails: tasks.map { task in
                TaskDetail(
                    title: task.title,
                    estimatedMinutes: task.estimatedMinutes,
                    actualMinutes: max(0, task.totalElapsedSeconds / 60),
                    completed: task.status == TaskStatus.done.rawValue
                )
            }
        )

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

        // 更新评分
        summary.grade = newGrade.grade.rawValue
        summary.summary = newGrade.summary
        summary.suggestion = newGrade.suggestion
        summary.gradingBasis = newGrade.gradingBasis
        summary.appealCount += 1
        try summaryRepo.update(summary)

        return summary
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

    /// 获取历史评分
    func fetchHistory(from: Date, to: Date) async throws -> [DailySummaryEntity] {
        try summaryRepo.fetchRange(from: from, to: to)
    }

    // MARK: - Private

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
}
