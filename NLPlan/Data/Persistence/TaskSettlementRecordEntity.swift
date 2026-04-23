import Foundation
import SwiftData

/// 必做项结算归档记录
@Model
final class TaskSettlementRecordEntity {
    @Attribute(.unique) var id: UUID
    var taskId: UUID
    var sourceIdeaId: UUID?
    var settlementDate: Date
    var title: String
    var estimatedMinutes: Int
    var actualMinutes: Int
    var priority: String
    var completed: Bool
    var sourceType: String
    var note: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        taskId: UUID,
        sourceIdeaId: UUID? = nil,
        settlementDate: Date,
        title: String,
        estimatedMinutes: Int,
        actualMinutes: Int,
        priority: String,
        completed: Bool,
        sourceType: String,
        note: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.taskId = taskId
        self.sourceIdeaId = sourceIdeaId
        self.settlementDate = settlementDate
        self.title = title
        self.estimatedMinutes = estimatedMinutes
        self.actualMinutes = actualMinutes
        self.priority = priority
        self.completed = completed
        self.sourceType = sourceType
        self.note = note
        self.createdAt = createdAt
    }
}
