import Foundation
import SwiftData

/// 项目备注记录
@Model
final class ProjectNoteEntity {
    @Attribute(.unique) var id: UUID
    var content: String
    var createdAt: Date
    var updatedAt: Date
    var projectId: UUID

    init(
        id: UUID = UUID(),
        content: String,
        projectId: UUID,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.content = content
        self.projectId = projectId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
