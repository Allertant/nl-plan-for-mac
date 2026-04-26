import Foundation

/// 日统计数据（不持久化，运行时计算用）
struct DayStats: Sendable {
    let totalTasks: Int
    let completedTasks: Int
    let totalPlannedMinutes: Int
    let totalActualMinutes: Int
    let deviationRate: Double
    let extraCompleted: Int

    var completionRate: Double {
        guard totalTasks > 0 else { return 0 }
        return Double(completedTasks) / Double(totalTasks)
    }

    /// 基于规则的基础评分（降级方案）
    var fallbackGrade: Grade {
        Grade.fromCompletionRate(completionRate)
    }
}
