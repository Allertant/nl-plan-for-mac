import Foundation
import SwiftData

/// 项目安排状态
enum ArrangementStatus: String, CaseIterable {
    case pending
    case inProgress = "in_progress"
    case done

    var displayName: String {
        switch self {
        case .pending: return "待安排"
        case .inProgress: return "进行中"
        case .done: return "已完成"
        }
    }
}

/// 项目安排记录
@Model
final class ProjectArrangementEntity {
    @Attribute(.unique) var id: UUID
    var projectId: UUID
    var content: String
    var estimatedMinutes: Int
    var status: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    @Transient
    var arrangementStatus: ArrangementStatus {
        ArrangementStatus(rawValue: status) ?? .pending
    }

    init(
        id: UUID = UUID(),
        projectId: UUID,
        content: String,
        estimatedMinutes: Int = 30,
        status: ArrangementStatus = .pending,
        sortOrder: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.projectId = projectId
        self.content = content
        self.estimatedMinutes = estimatedMinutes
        self.status = status.rawValue
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
