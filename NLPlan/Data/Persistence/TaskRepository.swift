import Foundation
import SwiftData

/// 任务数据操作仓库
/// Note: 使用 final class 而非 actor，因为 SwiftData ModelContext 需要在同一线程（主线程）使用
final class TaskRepository {

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Create

    func create(
        title: String,
        category: String,
        estimatedMinutes: Int,
        priority: TaskPriority = .medium,
        aiRecommended: Bool = false,
        recommendationReason: String? = nil,
        pool: TaskPool = .ideaPool,
        date: Date = .now
    ) throws -> TaskEntity {
        let task = TaskEntity(
            title: title,
            category: category,
            estimatedMinutes: estimatedMinutes,
            priority: priority.rawValue,
            aiRecommended: aiRecommended,
            recommendationReason: recommendationReason,
            pool: pool.rawValue,
            date: date,
            createdDate: .now
        )
        modelContext.insert(task)
        try modelContext.save()
        return task
    }

    // MARK: - Read

    func fetchById(_ id: UUID) throws -> TaskEntity? {
        let descriptor = FetchDescriptor<TaskEntity>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    func fetchTasks(date: Date, pool: TaskPool) throws -> [TaskEntity] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let poolRaw = pool.rawValue
        let descriptor = FetchDescriptor<TaskEntity>(
            predicate: #Predicate { task in
                task.pool == poolRaw &&
                task.date >= startOfDay &&
                task.date < endOfDay
            },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchAllIdeaPoolTasks() throws -> [TaskEntity] {
        let poolRaw = TaskPool.ideaPool.rawValue
        let descriptor = FetchDescriptor<TaskEntity>(
            predicate: #Predicate { $0.pool == poolRaw },
            sortBy: [SortDescriptor(\.createdDate, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchActiveRunningTasks() throws -> [TaskEntity] {
        let statusRaw = TaskStatus.running.rawValue
        let descriptor = FetchDescriptor<TaskEntity>(
            predicate: #Predicate { $0.status == statusRaw }
        )
        return try modelContext.fetch(descriptor)
    }

    // MARK: - Update

    func update(_ task: TaskEntity) throws {
        try modelContext.save()
    }

    func moveToMustDo(_ task: TaskEntity) throws {
        task.pool = TaskPool.mustDo.rawValue
        task.date = Date.now
        try modelContext.save()
    }

    func moveToIdeaPool(_ task: TaskEntity, markAttempted: Bool = false) throws {
        task.pool = TaskPool.ideaPool.rawValue
        task.status = TaskStatus.pending.rawValue
        if markAttempted {
            task.attempted = true
        }
        try modelContext.save()
    }

    func markComplete(_ task: TaskEntity) throws {
        task.status = TaskStatus.done.rawValue
        try modelContext.save()
    }

    func updateStatus(_ task: TaskEntity, status: TaskStatus) throws {
        task.status = status.rawValue
        try modelContext.save()
    }

    // MARK: - Delete

    func delete(_ task: TaskEntity) throws {
        modelContext.delete(task)
        try modelContext.save()
    }

    // MARK: - Batch Operations

    /// 将指定日期未完成的必做项移回想法池
    func migrateUnfinishedMustDo(date: Date) throws -> [TaskEntity] {
        let tasks = try fetchTasks(date: date, pool: .mustDo)
        let unfinished = tasks.filter { $0.status != TaskStatus.done.rawValue }
        for task in unfinished {
            let wasStarted = task.status == TaskStatus.running.rawValue
                || task.status == TaskStatus.paused.rawValue
                || !task.sessionLogs.isEmpty
            task.pool = TaskPool.ideaPool.rawValue
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
