import Foundation
import SwiftData

/// 项目备注记录
@Model
final class ProjectNoteEntity {
    @Attribute(.unique) var id: UUID
    var content: String
    var createdAt: Date
    var updatedAt: Date
    var ideaId: UUID?
    var projectId: UUID?

    init(
        id: UUID = UUID(),
        content: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        ideaId: UUID? = nil,
        projectId: UUID? = nil
    ) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.ideaId = ideaId
        self.projectId = projectId
    }
}
