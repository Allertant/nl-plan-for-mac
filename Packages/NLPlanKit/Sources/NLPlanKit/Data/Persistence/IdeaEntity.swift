import Foundation
import SwiftData

/// 长期想法实体。只表达“想法池中的长期对象”，不表达某天承诺执行的必做项。
@Model
final class IdeaEntity {
    @Attribute(.unique) var id: UUID
    var title: String
    var category: String
    var estimatedMinutes: Int?
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
    var projectDescription: String?
    var planningBackground: String?
    var planningResearchPrompt: String?
    var planningResearchPromptReason: String?
    var projectRecommendationContextUpdatedAt: Date?
    var projectRecommendationSummary: String?
    var projectRecommendationSummaryGeneratedAt: Date?
    var projectRecommendationSummarySourceUpdatedAt: Date?
    var deadline: Date?
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

    /// 显示用截止时间字符串（同年省略年份）
    @Transient
    var deadlineDisplayString: String? {
        guard let deadline else { return nil }
        let cal = Calendar.current
        let now = Date()
        let showYear = cal.component(.year, from: deadline) != cal.component(.year, from: now)
        let month = cal.component(.month, from: deadline)
        let day = cal.component(.day, from: deadline)
        let hour = cal.component(.hour, from: deadline)
        let minute = cal.component(.minute, from: deadline)
        let hasTime = !(hour == 0 && minute == 0)

        if showYear {
            let year = cal.component(.year, from: deadline)
            if hasTime {
                return String(format: "%d-%d-%d %02d:%02d", year, month, day, hour, minute)
            }
            return "\(year)-\(month)-\(day)"
        } else {
            if hasTime {
                return String(format: "%d-%d %02d:%02d", month, day, hour, minute)
            }
            return "\(month)-\(day)"
        }
    }

    init(
        id: UUID = UUID(),
        title: String,
        category: String,
        estimatedMinutes: Int? = nil,
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
        projectDescription: String? = nil,
        planningBackground: String? = nil,
        planningResearchPrompt: String? = nil,
        planningResearchPromptReason: String? = nil,
        projectRecommendationContextUpdatedAt: Date? = nil,
        projectRecommendationSummary: String? = nil,
        projectRecommendationSummaryGeneratedAt: Date? = nil,
        projectRecommendationSummarySourceUpdatedAt: Date? = nil,
        deadline: Date? = nil
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
        self.projectDescription = projectDescription
        self.planningBackground = planningBackground
        self.planningResearchPrompt = planningResearchPrompt
        self.planningResearchPromptReason = planningResearchPromptReason
        self.projectRecommendationContextUpdatedAt = projectRecommendationContextUpdatedAt
        self.projectRecommendationSummary = projectRecommendationSummary
        self.projectRecommendationSummaryGeneratedAt = projectRecommendationSummaryGeneratedAt
        self.projectRecommendationSummarySourceUpdatedAt = projectRecommendationSummarySourceUpdatedAt
        self.deadline = deadline
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
