import Foundation
import SwiftData

/// 将旧 TaskEntity 单表数据复制到新的 IdeaEntity / DailyTaskEntity。
/// 迁移保持幂等，不删除旧数据，直到业务路径完全切换后再考虑清理。
final class TaskSplitMigrationService {

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func run() throws {
        let legacyTasks = try fetchLegacyTasks()
        for task in legacyTasks where task.pool == TaskPool.ideaPool.rawValue {
            _ = try ensureIdea(for: task)
        }

        for task in legacyTasks where task.pool == TaskPool.mustDo.rawValue {
            _ = try ensureDailyTask(for: task)
        }

        try refreshIdeaLifecycleFromDailyTasks()
        try modelContext.save()
    }

    private func fetchLegacyTasks() throws -> [TaskEntity] {
        let descriptor = FetchDescriptor<TaskEntity>(
            sortBy: [SortDescriptor(\.createdDate, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func fetchIdea(migratedFromTaskId taskId: UUID) throws -> IdeaEntity? {
        let descriptor = FetchDescriptor<IdeaEntity>(
            predicate: #Predicate { $0.migratedFromTaskId == taskId }
        )
        return try modelContext.fetch(descriptor).first
    }

    private func fetchDailyTask(migratedFromTaskId taskId: UUID) throws -> DailyTaskEntity? {
        let descriptor = FetchDescriptor<DailyTaskEntity>(
            predicate: #Predicate { $0.migratedFromTaskId == taskId }
        )
        return try modelContext.fetch(descriptor).first
    }

    private func fetchLegacyTask(id: UUID) throws -> TaskEntity? {
        let descriptor = FetchDescriptor<TaskEntity>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    private func ensureIdea(for task: TaskEntity) throws -> IdeaEntity {
        if let existing = try fetchIdea(migratedFromTaskId: task.id) {
            return existing
        }

        let status: IdeaStatus
        if task.status == TaskStatus.done.rawValue {
            status = .completed
        } else if task.attempted {
            status = .attempted
        } else {
            status = .pending
        }

        let idea = IdeaEntity(
            id: task.id,
            title: task.title,
            category: task.category,
            estimatedMinutes: task.estimatedMinutes,
            priority: task.priority,
            aiRecommended: task.aiRecommended,
            recommendationReason: task.recommendationReason,
            sortOrder: task.sortOrder,
            status: status.rawValue,
            createdDate: task.createdDate,
            updatedAt: task.createdDate,
            attempted: task.attempted,
            note: task.note,
            isProject: task.isProjectTask,
            projectDecisionSource: task.projectDecisionSource,
            projectProgress: task.projectProgress,
            projectProgressSummary: task.projectProgressSummary,
            projectProgressUpdatedAt: task.projectProgressUpdatedAt,
            migratedFromTaskId: task.id
        )
        modelContext.insert(idea)
        return idea
    }

    private func ensureDailyTask(for task: TaskEntity) throws -> DailyTaskEntity {
        if let existing = try fetchDailyTask(migratedFromTaskId: task.id) {
            return existing
        }

        let sourceIdea = try migratedSourceIdea(for: task)
        let dailyTask = DailyTaskEntity(
            id: task.id,
            title: task.title,
            category: task.category,
            estimatedMinutes: task.estimatedMinutes,
            priority: task.priority,
            aiRecommended: task.aiRecommended,
            recommendationReason: task.recommendationReason,
            sortOrder: task.sortOrder,
            status: task.status,
            date: task.date,
            createdDate: task.createdDate,
            updatedAt: task.createdDate,
            attempted: task.attempted,
            note: task.note,
            sourceIdeaId: sourceIdea?.id,
            sourceType: sourceType(for: task, sourceIdea: sourceIdea).rawValue,
            migratedFromTaskId: task.id
        )
        modelContext.insert(dailyTask)
        return dailyTask
    }

    private func migratedSourceIdea(for task: TaskEntity) throws -> IdeaEntity? {
        guard let sourceIdeaId = task.sourceIdeaId,
              let legacySource = try fetchLegacyTask(id: sourceIdeaId) else {
            return nil
        }
        return try ensureIdea(for: legacySource)
    }

    private func sourceType(for task: TaskEntity, sourceIdea: IdeaEntity?) -> DailyTaskSourceType {
        if let sourceIdea {
            return sourceIdea.isProject ? .project : .idea
        }
        return task.sourceIdeaId == nil ? .none : .idea
    }

    private func refreshIdeaLifecycleFromDailyTasks() throws {
        let descriptor = FetchDescriptor<DailyTaskEntity>(
            predicate: #Predicate { $0.sourceIdeaId != nil }
        )
        let dailyTasks = try modelContext.fetch(descriptor)
        let activeByIdeaId = Dictionary(grouping: dailyTasks.filter { $0.status != TaskStatus.done.rawValue }) { $0.sourceIdeaId }

        for (sourceId, activeTasks) in activeByIdeaId {
            guard let sourceId, !activeTasks.isEmpty else { continue }
            let ideaDescriptor = FetchDescriptor<IdeaEntity>(
                predicate: #Predicate { $0.id == sourceId }
            )
            guard let idea = try modelContext.fetch(ideaDescriptor).first else { continue }
            if !idea.isProject && idea.status != IdeaStatus.completed.rawValue && idea.status != IdeaStatus.archived.rawValue {
                idea.status = IdeaStatus.inProgress.rawValue
                idea.updatedAt = .now
            }
        }
    }
}
