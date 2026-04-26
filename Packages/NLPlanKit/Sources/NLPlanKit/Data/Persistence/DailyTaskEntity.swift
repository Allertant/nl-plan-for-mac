import Foundation
import SwiftData

/// 某一天用户确认执行的必做项。只表达”当天计划”，长期想法信息通过 sourceIdeaId 引用。
/// - note: 任务备注（用户在添加/编辑必做项时填写）
/// - incompletionReason: 未完成原因说明（日终结算时填写，原字段名 settlementNote）
@Model
final class DailyTaskEntity {
    @Attribute(.unique) var id: UUID
    var title: String
    var category: String
    var estimatedMinutes: Int
    var priority: String
    var aiRecommended: Bool
    var recommendationReason: String?
    var sortOrder: Int
    var status: String
    var date: Date
    var createdDate: Date
    var updatedAt: Date
    var attempted: Bool
    var note: String?
    @Attribute(originalName: "settlementNote") var incompletionReason: String?
    var sourceIdeaId: UUID?
    var sourceType: String
    var isSettled: Bool = false
    var settledAt: Date?
    var actualMinutes: Int?

    @Transient
    var taskStatus: TaskStatus {
        get { TaskStatus(rawValue: status) ?? .pending }
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
        status: String = TaskStatus.pending.rawValue,
        date: Date = .now,
        createdDate: Date = .now,
        updatedAt: Date = .now,
        attempted: Bool = false,
        note: String? = nil,
        incompletionReason: String? = nil,
        sourceIdeaId: UUID? = nil,
        sourceType: String = DailyTaskSourceType.none.rawValue,
        isSettled: Bool = false,
        settledAt: Date? = nil,
        actualMinutes: Int? = nil
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
        self.date = date
        self.createdDate = createdDate
        self.updatedAt = updatedAt
        self.attempted = attempted
        self.note = note
        self.incompletionReason = incompletionReason
        self.sourceIdeaId = sourceIdeaId
        self.sourceType = sourceType
        self.isSettled = isSettled
        self.settledAt = settledAt
        self.actualMinutes = actualMinutes
    }
}

enum DailyTaskSourceType: String, CaseIterable {
    case idea
    case project
    case none

    var displayName: String {
        switch self {
        case .idea: return "普通想法来源必做项"
        case .project: return "项目链接必做项"
        case .none: return "无来源必做项"
        }
    }
}
