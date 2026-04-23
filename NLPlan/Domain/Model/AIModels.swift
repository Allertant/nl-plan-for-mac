import Foundation

/// AI 解析后的任务模型（DTO，非持久化）
struct ParsedTask: Sendable, Identifiable, Codable {
    let id: UUID
    var title: String
    var category: String
    var estimatedMinutes: Int
    let recommended: Bool
    let reason: String
    var isProject: Bool?

    init(
        id: UUID = UUID(),
        title: String,
        category: String,
        estimatedMinutes: Int,
        recommended: Bool,
        reason: String,
        isProject: Bool? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.estimatedMinutes = estimatedMinutes
        self.recommended = recommended
        self.reason = reason
        self.isProject = isProject
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
    let isProject: Bool
}

/// AI 推荐结果（单条）
struct TaskRecommendation: Sendable, Identifiable, Equatable {
    let id = UUID()
    let taskId: UUID?
    let sourceIdeaId: UUID?
    let title: String
    let category: String
    let estimatedMinutes: Int
    let reason: String

    static func == (lhs: TaskRecommendation, rhs: TaskRecommendation) -> Bool {
        lhs.taskId == rhs.taskId &&
        lhs.sourceIdeaId == rhs.sourceIdeaId &&
        lhs.title == rhs.title
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

struct ProjectClassificationInput: Sendable {
    let id: UUID
    let title: String
    let category: String
    let estimatedMinutes: Int
}

struct ProjectClassification: Sendable, Equatable {
    let ideaId: UUID
    let isProject: Bool
    let reason: String
}

struct ProjectLinkedTaskInput: Sendable {
    let id: UUID
    let title: String
    let estimatedMinutes: Int
    let completed: Bool
}

struct ProjectProgressInput: Sendable {
    let ideaId: UUID
    let title: String
    let category: String
    let completedTasks: [ProjectLinkedTaskInput]
    let pendingTasks: [ProjectLinkedTaskInput]
}

struct ProjectProgressAnalysis: Sendable, Equatable {
    let ideaId: UUID
    let progress: Double
    let summary: String
}

/// 日终评分输入
struct DailySummaryInput: Sendable {
    let settlementDate: String
    let totalTasks: Int
    let completedTasks: Int
    let totalPlannedMinutes: Int
    let totalActualMinutes: Int
    let deviationRate: Double
    let extraCompleted: Int
    let taskDetails: [TaskDetail]

    init(
        settlementDate: String = "",
        totalTasks: Int,
        completedTasks: Int,
        totalPlannedMinutes: Int,
        totalActualMinutes: Int,
        deviationRate: Double,
        extraCompleted: Int,
        taskDetails: [TaskDetail]
    ) {
        self.settlementDate = settlementDate
        self.totalTasks = totalTasks
        self.completedTasks = completedTasks
        self.totalPlannedMinutes = totalPlannedMinutes
        self.totalActualMinutes = totalActualMinutes
        self.deviationRate = deviationRate
        self.extraCompleted = extraCompleted
        self.taskDetails = taskDetails
    }

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
    let priority: String
    let sourceType: String
    let note: String?

    init(
        title: String,
        estimatedMinutes: Int,
        actualMinutes: Int,
        completed: Bool,
        priority: String = "medium",
        sourceType: String = "无来源",
        note: String? = nil
    ) {
        self.title = title
        self.estimatedMinutes = estimatedMinutes
        self.actualMinutes = actualMinutes
        self.completed = completed
        self.priority = priority
        self.sourceType = sourceType
        self.note = note
    }
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
