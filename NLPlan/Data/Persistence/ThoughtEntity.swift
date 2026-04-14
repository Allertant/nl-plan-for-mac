import Foundation
import SwiftData

/// 想法输入实体
@Model
final class ThoughtEntity {
    @Attribute(.unique) var id: UUID
    var rawText: String
    var createdAt: Date
    var processed: Bool

    @Relationship(deleteRule: .cascade)
    var tasks: [TaskEntity] = []

    init(
        id: UUID = UUID(),
        rawText: String,
        createdAt: Date = .now,
        processed: Bool = false
    ) {
        self.id = id
        self.rawText = rawText
        self.createdAt = createdAt
        self.processed = processed
    }
}
