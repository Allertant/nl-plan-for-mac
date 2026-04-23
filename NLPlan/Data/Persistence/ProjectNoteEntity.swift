import Foundation
import SwiftData

/// 项目备注记录
@Model
final class ProjectNoteEntity {
    @Attribute(.unique) var id: UUID
    var content: String
    var createdAt: Date
    var updatedAt: Date

    var projectTask: TaskEntity?

    init(
        id: UUID = UUID(),
        content: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        projectTask: TaskEntity? = nil
    ) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.projectTask = projectTask
    }
}
