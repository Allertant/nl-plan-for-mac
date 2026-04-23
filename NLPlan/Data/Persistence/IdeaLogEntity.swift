import Foundation
import SwiftData

/// 想法生命周期日志，用于记录尝试、完成、重新安排和人工备注。
@Model
final class IdeaLogEntity {
    @Attribute(.unique) var id: UUID
    var ideaId: UUID
    var type: String
    var content: String
    var createdAt: Date
    var relatedTaskId: UUID?
    var settlementDate: Date?

    @Transient
    var logType: IdeaLogType {
        get { IdeaLogType(rawValue: type) ?? .note }
        set { type = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        ideaId: UUID,
        type: String = IdeaLogType.note.rawValue,
        content: String,
        createdAt: Date = .now,
        relatedTaskId: UUID? = nil,
        settlementDate: Date? = nil
    ) {
        self.id = id
        self.ideaId = ideaId
        self.type = type
        self.content = content
        self.createdAt = createdAt
        self.relatedTaskId = relatedTaskId
        self.settlementDate = settlementDate
    }
}

enum IdeaLogType: String, CaseIterable {
    case attempted
    case completed
    case rescheduled
    case note
}
