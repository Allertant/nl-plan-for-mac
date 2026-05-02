import Foundation
import SwiftData

/// 项目表仓库。阶段 1 先提供独立项目数据落点与最小查询骨架。
final class ProjectRepository {

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func create(
        id: UUID = UUID(),
        title: String,
        category: String,
        priority: TaskPriority = .medium,
        sortOrder: Int = 0,
        status: ProjectStatus = .pending,
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
        deadline: Date? = nil,
        createdDate: Date = .now
    ) throws -> ProjectEntity {
        let project = ProjectEntity(
            id: id,
            title: title,
            category: category,
            priority: priority.rawValue,
            sortOrder: sortOrder,
            status: status.rawValue,
            createdDate: createdDate,
            updatedAt: .now,
            projectDecisionSource: projectDecisionSource,
            projectProgress: projectProgress,
            projectProgressSummary: projectProgressSummary,
            projectProgressUpdatedAt: projectProgressUpdatedAt,
            projectDescription: projectDescription,
            planningBackground: planningBackground,
            planningResearchPrompt: planningResearchPrompt,
            planningResearchPromptReason: planningResearchPromptReason,
            projectRecommendationContextUpdatedAt: projectRecommendationContextUpdatedAt ?? .now,
            projectRecommendationSummary: projectRecommendationSummary,
            projectRecommendationSummaryGeneratedAt: projectRecommendationSummaryGeneratedAt,
            projectRecommendationSummarySourceUpdatedAt: projectRecommendationSummarySourceUpdatedAt,
            deadline: deadline
        )
        modelContext.insert(project)
        try modelContext.save()
        return project
    }

    func fetchById(_ id: UUID) throws -> ProjectEntity? {
        let descriptor = FetchDescriptor<ProjectEntity>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    func fetchVisibleProjects() throws -> [ProjectEntity] {
        let archived = ProjectStatus.archived.rawValue
        let descriptor = FetchDescriptor<ProjectEntity>(
            predicate: #Predicate { project in
                project.status != archived
            },
            sortBy: [SortDescriptor(\.createdDate, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchRecommendationCandidates() throws -> [ProjectEntity] {
        let archived = ProjectStatus.archived.rawValue
        let descriptor = FetchDescriptor<ProjectEntity>(
            predicate: #Predicate { project in
                project.status != archived
            },
            sortBy: [SortDescriptor(\.createdDate, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func update(_ project: ProjectEntity) throws {
        project.updatedAt = .now
        try modelContext.save()
    }

    func touchRecommendationContext(_ project: ProjectEntity, at date: Date = .now) throws {
        project.projectRecommendationContextUpdatedAt = date
        project.updatedAt = date
        try modelContext.save()
    }

    func delete(_ project: ProjectEntity) throws {
        modelContext.delete(project)
        try modelContext.save()
    }

    // MARK: - Project Notes

    func createProjectNote(projectId: UUID, content: String) throws -> ProjectNoteEntity {
        let note = ProjectNoteEntity(content: content, projectId: projectId)
        modelContext.insert(note)
        try modelContext.save()
        return note
    }

    func fetchProjectNotes(projectId: UUID) throws -> [ProjectNoteEntity] {
        let targetId = projectId
        let descriptor = FetchDescriptor<ProjectNoteEntity>(
            predicate: #Predicate { $0.projectId == targetId },
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

    // MARK: - Project Planning

    func updateDescription(_ project: ProjectEntity, description: String?) throws {
        project.projectDescription = description
        project.updatedAt = .now
        try modelContext.save()
    }

    func updatePlanningBackground(_ project: ProjectEntity, planningBackground: String?) throws {
        project.planningBackground = planningBackground
        project.updatedAt = .now
        try modelContext.save()
    }

    func updateTitle(_ project: ProjectEntity, title: String) throws {
        project.title = title
        project.updatedAt = .now
        try modelContext.save()
    }

    func updatePlanningResearch(_ project: ProjectEntity, prompt: String?, reason: String?) throws {
        project.planningResearchPrompt = prompt
        project.planningResearchPromptReason = reason
        project.updatedAt = .now
        try modelContext.save()
    }
}
