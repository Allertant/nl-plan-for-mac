import Foundation
import SwiftData

/// 想法表仓库
final class IdeaRepository {

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func create(
        id: UUID = UUID(),
        title: String,
        category: String,
        estimatedMinutes: Int,
        priority: TaskPriority = .medium,
        aiRecommended: Bool = false,
        recommendationReason: String? = nil,
        sortOrder: Int = 0,
        status: IdeaStatus = .pending,
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
        createdDate: Date = .now
    ) throws -> IdeaEntity {
        let idea = IdeaEntity(
            id: id,
            title: title,
            category: category,
            estimatedMinutes: estimatedMinutes,
            priority: priority.rawValue,
            aiRecommended: aiRecommended,
            recommendationReason: recommendationReason,
            sortOrder: sortOrder,
            status: status.rawValue,
            createdDate: createdDate,
            updatedAt: .now,
            attempted: attempted,
            note: note,
            isProject: isProject,
            projectDecisionSource: projectDecisionSource,
            projectProgress: projectProgress,
            projectProgressSummary: projectProgressSummary,
            projectProgressUpdatedAt: projectProgressUpdatedAt,
            projectDescription: projectDescription,
            planningBackground: planningBackground,
            planningResearchPrompt: planningResearchPrompt,
            planningResearchPromptReason: planningResearchPromptReason
        )
        modelContext.insert(idea)
        try modelContext.save()
        return idea
    }

    func fetchById(_ id: UUID) throws -> IdeaEntity? {
        let descriptor = FetchDescriptor<IdeaEntity>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    func fetchVisibleIdeas() throws -> [IdeaEntity] {
        let completed = IdeaStatus.completed.rawValue
        let archived = IdeaStatus.archived.rawValue
        let descriptor = FetchDescriptor<IdeaEntity>(
            predicate: #Predicate { idea in
                idea.status != completed && idea.status != archived
            },
            sortBy: [SortDescriptor(\.createdDate, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchRecommendationCandidates() throws -> [IdeaEntity] {
        let pending = IdeaStatus.pending.rawValue
        let attempted = IdeaStatus.attempted.rawValue
        let descriptor = FetchDescriptor<IdeaEntity>(
            predicate: #Predicate { idea in
                idea.status == pending || idea.status == attempted
            },
            sortBy: [SortDescriptor(\.createdDate, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func update(_ idea: IdeaEntity) throws {
        idea.updatedAt = .now
        try modelContext.save()
    }

    func delete(_ idea: IdeaEntity) throws {
        modelContext.delete(idea)
        try modelContext.save()
    }

    // MARK: - Project Notes

    func createProjectNote(ideaId: UUID, content: String) throws -> ProjectNoteEntity {
        let note = ProjectNoteEntity(content: content, ideaId: ideaId)
        modelContext.insert(note)
        try modelContext.save()
        return note
    }

    func fetchProjectNotes(ideaId: UUID) throws -> [ProjectNoteEntity] {
        let targetId = ideaId
        let descriptor = FetchDescriptor<ProjectNoteEntity>(
            predicate: #Predicate { $0.ideaId == targetId },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchProjectNoteById(_ id: UUID) throws -> ProjectNoteEntity? {
        let descriptor = FetchDescriptor<ProjectNoteEntity>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    func updateProjectNote(_ note: ProjectNoteEntity, content: String) throws {
        note.content = content
        note.updatedAt = .now
        try modelContext.save()
    }
}
