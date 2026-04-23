import Foundation
import SwiftData

/// 新想法表仓库。迁移完成前与旧 TaskRepository 并存。
final class IdeaRepository {

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func create(
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
        migratedFromTaskId: UUID? = nil
    ) throws -> IdeaEntity {
        let idea = IdeaEntity(
            title: title,
            category: category,
            estimatedMinutes: estimatedMinutes,
            priority: priority.rawValue,
            aiRecommended: aiRecommended,
            recommendationReason: recommendationReason,
            sortOrder: sortOrder,
            status: status.rawValue,
            attempted: attempted,
            note: note,
            isProject: isProject,
            projectDecisionSource: projectDecisionSource,
            projectProgress: projectProgress,
            projectProgressSummary: projectProgressSummary,
            projectProgressUpdatedAt: projectProgressUpdatedAt,
            migratedFromTaskId: migratedFromTaskId
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

    func fetchByMigratedTaskId(_ taskId: UUID) throws -> IdeaEntity? {
        let descriptor = FetchDescriptor<IdeaEntity>(
            predicate: #Predicate { $0.migratedFromTaskId == taskId }
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

    func addLog(
        ideaId: UUID,
        type: IdeaLogType,
        content: String,
        relatedTaskId: UUID? = nil,
        settlementDate: Date? = nil
    ) throws -> IdeaLogEntity {
        let log = IdeaLogEntity(
            ideaId: ideaId,
            type: type.rawValue,
            content: content,
            relatedTaskId: relatedTaskId,
            settlementDate: settlementDate
        )
        modelContext.insert(log)
        try modelContext.save()
        return log
    }

    func fetchLogs(ideaId: UUID) throws -> [IdeaLogEntity] {
        let targetId = ideaId
        let descriptor = FetchDescriptor<IdeaLogEntity>(
            predicate: #Predicate { $0.ideaId == targetId },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }
}
