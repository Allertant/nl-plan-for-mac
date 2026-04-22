import Foundation

/// AI 解析后的任务模型（DTO，非持久化）
struct ParsedTask: Sendable, Identifiable, Codable {
    let id: UUID
    var title: String
    var category: String
    var estimatedMinutes: Int
    let recommended: Bool
    let reason: String

    init(id: UUID = UUID(), title: String, category: String, estimatedMinutes: Int, recommended: Bool, reason: String) {
        self.id = id
        self.title = title
        self.category = category
        self.estimatedMinutes = estimatedMinutes
        self.recommended = recommended
        self.reason = reason
    }
}

/// AI 推荐输入（想法池/必做项任务摘要）
struct TaskRecommendationInput: Sendable {
    let id: UUID
    let title: String
    let category: String
    let estimatedMinutes: Int
    let attempted: Bool
    let status: String
}

/// AI 推荐结果（单条）
struct TaskRecommendation: Sendable, Identifiable, Equatable {
    let id = UUID()
    let taskId: UUID
    let reason: String

    static func == (lhs: TaskRecommendation, rhs: TaskRecommendation) -> Bool {
        lhs.taskId == rhs.taskId
    }
}

/// AI 推荐响应（整体）
struct RecommendationResult: Sendable, Equatable {
    let recommendations: [TaskRecommendation]
    let overallReason: String
}

/// AI 清理建议（单条）
struct CleanupSuggestion: Sendable, Identifiable, Equatable {
    let id = UUID()
    let taskId: UUID
    let reason: String

    static func == (lhs: CleanupSuggestion, rhs: CleanupSuggestion) -> Bool {
        lhs.taskId == rhs.taskId
    }
}

/// AI 清理响应（整体）
struct CleanupResult: Sendable, Equatable {
    let items: [CleanupSuggestion]
    let overallReason: String
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
