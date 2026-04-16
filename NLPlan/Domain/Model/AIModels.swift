import Foundation

/// AI 解析后的任务模型（DTO，非持久化）
struct ParsedTask: Sendable, Identifiable {
    let id = UUID()
    var title: String
    var category: String
    var estimatedMinutes: Int
    let recommended: Bool
    let reason: String
}

/// 日终评分输入
struct DailySummaryInput: Sendable {
    let totalTasks: Int
    let completedTasks: Int
    let totalPlannedMinutes: Int
    let totalActualMinutes: Int
    let deviationRate: Double
    let extraCompleted: Int
    let taskDetails: [TaskDetail]

    var completionRate: Double {
        guard totalTasks > 0 else { return 0 }
        return Double(completedTasks) / Double(totalTasks)
    }
}

/// 单个任务的完成详情（用于 AI 评分输入）
struct TaskDetail: Sendable, Identifiable {
    let id = UUID()
    let title: String
    let estimatedMinutes: Int
    let actualMinutes: Int
    let completed: Bool
}

/// 日终评分输出
struct DailyGrade: Sendable {
    let grade: Grade
    let summary: String
    let stats: GradeStats
    let suggestion: String
    let gradingBasis: String
}

/// 评分统计数据
struct GradeStats: Sendable {
    let totalTasks: Int
    let completedTasks: Int
    let totalPlannedMinutes: Int
    let totalActualMinutes: Int
    let deviationRate: Double
    let extraCompleted: Int
}
