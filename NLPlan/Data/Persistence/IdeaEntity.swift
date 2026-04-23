import Foundation
import SwiftData

/// 长期想法实体。只表达“想法池中的长期对象”，不表达某天承诺执行的必做项。
@Model
final class IdeaEntity {
    @Attribute(.unique) var id: UUID
    var title: String
    var category: String
    var estimatedMinutes: Int
    var priority: String
    var aiRecommended: Bool
    var recommendationReason: String?
    var sortOrder: Int
    var status: String
    var createdDate: Date
    var updatedAt: Date
    var attempted: Bool
    var note: String?
    var isProject: Bool
    var projectDecisionSource: String?
    var projectProgress: Double?
    var projectProgressSummary: String?
    var projectProgressUpdatedAt: Date?
    var migratedFromTaskId: UUID?

    @Transient
    var ideaStatus: IdeaStatus {
        get { IdeaStatus(rawValue: status) ?? .pending }
        set { status = newValue.rawValue }
    }

    @Transient
    var taskPriority: TaskPriority {
        get { TaskPriority(rawValue: priority) ?? .medium }
        set { priority = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        title: String,
        category: String,
        estimatedMinutes: Int,
        priority: String = TaskPriority.medium.rawValue,
        aiRecommended: Bool = false,
        recommendationReason: String? = nil,
        sortOrder: Int = 0,
        status: String = IdeaStatus.pending.rawValue,
        createdDate: Date = .now,
        updatedAt: Date = .now,
        attempted: Bool = false,
        note: String? = nil,
        isProject: Bool = false,
        projectDecisionSource: String? = nil,
        projectProgress: Double? = nil,
        projectProgressSummary: String? = nil,
        projectProgressUpdatedAt: Date? = nil,
        migratedFromTaskId: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.estimatedMinutes = estimatedMinutes
        self.priority = priority
        self.aiRecommended = aiRecommended
        self.recommendationReason = recommendationReason
        self.sortOrder = sortOrder
        self.status = status
        self.createdDate = createdDate
        self.updatedAt = updatedAt
        self.attempted = attempted
        self.note = note
        self.isProject = isProject
        self.projectDecisionSource = projectDecisionSource
        self.projectProgress = projectProgress
        self.projectProgressSummary = projectProgressSummary
        self.projectProgressUpdatedAt = projectProgressUpdatedAt
        self.migratedFromTaskId = migratedFromTaskId
    }
}

enum IdeaStatus: String, CaseIterable {
    case pending
    case inProgress = "in_progress"
    case attempted
    case completed
    case archived

    var displayName: String {
        switch self {
        case .pending: return "待处理"
        case .inProgress: return "进行中"
        case .attempted: return "尝试过"
        case .completed: return "已完成"
        case .archived: return "已归档"
        }
    }
}
