import Foundation
import SwiftData

/// 新必做项表仓库。迁移完成前与旧 TaskRepository 并存。
final class DailyTaskRepository {

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
        status: TaskStatus = .pending,
        date: Date = .now,
        createdDate: Date = .now,
        attempted: Bool = false,
        note: String? = nil,
        sourceIdeaId: UUID? = nil,
        sourceType: DailyTaskSourceType = .none,
        migratedFromTaskId: UUID? = nil
    ) throws -> DailyTaskEntity {
        let task = DailyTaskEntity(
            id: id,
            title: title,
            category: category,
            estimatedMinutes: estimatedMinutes,
            priority: priority.rawValue,
            aiRecommended: aiRecommended,
            recommendationReason: recommendationReason,
            sortOrder: sortOrder,
            status: status.rawValue,
            date: date,
            createdDate: createdDate,
            updatedAt: .now,
            attempted: attempted,
            note: note,
            sourceIdeaId: sourceIdeaId,
            sourceType: sourceType.rawValue,
            migratedFromTaskId: migratedFromTaskId
        )
        modelContext.insert(task)
        try modelContext.save()
        return task
    }

    func fetchById(_ id: UUID) throws -> DailyTaskEntity? {
        let descriptor = FetchDescriptor<DailyTaskEntity>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    func fetchByMigratedTaskId(_ taskId: UUID) throws -> DailyTaskEntity? {
        let descriptor = FetchDescriptor<DailyTaskEntity>(
            predicate: #Predicate { $0.migratedFromTaskId == taskId }
        )
        return try modelContext.fetch(descriptor).first
    }

    func fetchTasks(date: Date) throws -> [DailyTaskEntity] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let descriptor = FetchDescriptor<DailyTaskEntity>(
            predicate: #Predicate { task in
                task.date >= startOfDay && task.date < endOfDay
            },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchActiveTasks(sourceIdeaId: UUID) throws -> [DailyTaskEntity] {
        let sourceId = sourceIdeaId
        let done = TaskStatus.done.rawValue
        let descriptor = FetchDescriptor<DailyTaskEntity>(
            predicate: #Predicate { task in
                task.sourceIdeaId == sourceId && task.status != done
            },
            sortBy: [SortDescriptor(\.createdDate, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchTasks(sourceIdeaId: UUID) throws -> [DailyTaskEntity] {
        let sourceId = sourceIdeaId
        let descriptor = FetchDescriptor<DailyTaskEntity>(
            predicate: #Predicate { task in
                task.sourceIdeaId == sourceId
            },
            sortBy: [SortDescriptor(\.createdDate, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchActiveRunningTasks() throws -> [DailyTaskEntity] {
        let statusRaw = TaskStatus.running.rawValue
        let descriptor = FetchDescriptor<DailyTaskEntity>(
            predicate: #Predicate { $0.status == statusRaw }
        )
        return try modelContext.fetch(descriptor)
    }

    func update(_ task: DailyTaskEntity) throws {
        task.updatedAt = .now
        try modelContext.save()
    }

    func deleteByMigratedTaskId(_ taskId: UUID) throws {
        guard let task = try fetchByMigratedTaskId(taskId) else { return }
        modelContext.delete(task)
        try modelContext.save()
    }

    func delete(_ task: DailyTaskEntity) throws {
        modelContext.delete(task)
        try modelContext.save()
    }

    func save() throws {
        try modelContext.save()
    }
}
