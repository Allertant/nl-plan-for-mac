import Foundation
import SwiftData

/// 项目实体。只表达长期项目对象，不承载普通想法语义。
@Model
final class ProjectEntity {
    @Attribute(.unique) var id: UUID
    var title: String
    var category: String
    var priority: String
    var sortOrder: Int
    var status: String
    var createdDate: Date
    var updatedAt: Date
    var pinnedState: Bool?
    var pinnedAt: Date?
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
    var projectStatus: ProjectStatus {
        get { ProjectStatus(rawValue: status) ?? .pending }
        set { status = newValue.rawValue }
    }

    @Transient
    var taskPriority: TaskPriority {
        get { TaskPriority(rawValue: priority) ?? .medium }
        set { priority = newValue.rawValue }
    }

    @Transient
    var isPinned: Bool {
        get { pinnedState ?? false }
        set { pinnedState = newValue }
    }

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
        priority: String = TaskPriority.medium.rawValue,
        sortOrder: Int = 0,
        status: String = ProjectStatus.pending.rawValue,
        createdDate: Date = .now,
        updatedAt: Date = .now,
        isPinned: Bool = false,
        pinnedAt: Date? = nil,
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
        self.priority = priority
        self.sortOrder = sortOrder
        self.status = status
        self.createdDate = createdDate
        self.updatedAt = updatedAt
        self.pinnedState = isPinned
        self.pinnedAt = pinnedAt
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

enum ProjectStatus: String, CaseIterable {
    case pending
    case active
    case archived

    var displayName: String {
        switch self {
        case .pending: return "待推进"
        case .active: return "进行中"
        case .archived: return "已归档"
        }
    }
}
