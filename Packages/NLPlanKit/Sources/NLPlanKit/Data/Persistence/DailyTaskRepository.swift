import Foundation
import SwiftData

/// 必做项表仓库
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
        sourceProjectId: UUID? = nil,
        arrangementId: UUID? = nil,
        sourceType: DailyTaskSourceType = .none
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
            sourceProjectId: sourceProjectId,
            arrangementId: arrangementId,
            sourceType: sourceType.rawValue
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

    func fetchTasks(date: Date) throws -> [DailyTaskEntity] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let descriptor = FetchDescriptor<DailyTaskEntity>(
            predicate: #Predicate { task in
                task.date >= startOfDay && task.date < endOfDay && task.isSettled == false
            },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchAllTasks(date: Date) throws -> [DailyTaskEntity] {
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
                task.sourceIdeaId == sourceId && task.status != done && task.isSettled == false
            },
            sortBy: [SortDescriptor(\.createdDate, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchActiveTask(arrangementId: UUID) throws -> DailyTaskEntity? {
        let arrangementId = arrangementId
        let descriptor = FetchDescriptor<DailyTaskEntity>(
            predicate: #Predicate { task in
                task.arrangementId == arrangementId && task.isSettled == false
            },
            sortBy: [SortDescriptor(\.createdDate, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).first
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
            predicate: #Predicate { $0.status == statusRaw && $0.isSettled == false }
        )
        return try modelContext.fetch(descriptor)
    }

    func update(_ task: DailyTaskEntity) throws {
        task.updatedAt = .now
        try modelContext.save()
    }

    func deleteById(_ id: UUID) throws {
        guard let task = try fetchById(id) else { return }
        modelContext.delete(task)
        try modelContext.save()
    }

    func fetchSettledTasks(sourceIdeaId: UUID) throws -> [DailyTaskEntity] {
        let sourceId = sourceIdeaId
        let descriptor = FetchDescriptor<DailyTaskEntity>(
            predicate: #Predicate { task in
                task.sourceIdeaId == sourceId && task.isSettled == true
            },
            sortBy: [SortDescriptor(\.settledAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchTasks(sourceProjectId: UUID) throws -> [DailyTaskEntity] {
        let sourceId = sourceProjectId
        let descriptor = FetchDescriptor<DailyTaskEntity>(
            predicate: #Predicate { task in
                task.sourceProjectId == sourceId
            },
            sortBy: [SortDescriptor(\.createdDate, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchSettledTasks(sourceProjectId: UUID) throws -> [DailyTaskEntity] {
        let sourceId = sourceProjectId
        let descriptor = FetchDescriptor<DailyTaskEntity>(
            predicate: #Predicate { task in
                task.sourceProjectId == sourceId && task.isSettled == true
            },
            sortBy: [SortDescriptor(\.settledAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func save() throws {
        try modelContext.save()
    }

    /// 将指定日期未完成的必做项移回想法池（在 DailyTaskEntity 上标记回退）
    func migrateUnfinishedMustDo(date: Date) throws -> [DailyTaskEntity] {
        let tasks = try fetchTasks(date: date)
        let unfinished = tasks.filter { $0.status != TaskStatus.done.rawValue }
        for task in unfinished {
            let wasStarted = task.status == TaskStatus.running.rawValue
                || task.status == TaskStatus.paused.rawValue
            task.status = TaskStatus.pending.rawValue
            task.date = Date.now
            if wasStarted {
                task.attempted = true
            }
        }
        try modelContext.save()
        return unfinished
    }
}
