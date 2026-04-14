import Foundation
import SwiftData

/// 任务实体
@Model
final class TaskEntity {
    @Attribute(.unique) var id: UUID
    var title: String
    var category: String
    var estimatedMinutes: Int
    var priority: String     // "high" / "medium" / "low"
    var aiRecommended: Bool
    var recommendationReason: String?
    var pool: String         // "idea_pool" / "must_do"
    var sortOrder: Int
    var status: String       // "pending" / "running" / "paused" / "done"
    var date: Date           // 任务所属日期
    var createdDate: Date    // 任务创建日期（跨天迁移后 date 变化但 createdDate 不变）
    var attempted: Bool      // 是否曾经尝试过（跨天迁移标记）

    @Relationship(deleteRule: .cascade, inverse: \SessionLogEntity.task)
    var sessionLogs: [SessionLogEntity] = []

    @Transient
    var totalElapsedSeconds: Int {
        sessionLogs.reduce(0) { $0 + $1.durationSeconds }
    }

    @Transient
    var taskPool: TaskPool {
        get { TaskPool(rawValue: pool) ?? .ideaPool }
        set { pool = newValue.rawValue }
    }

    @Transient
    var taskStatus: TaskStatus {
        get { TaskStatus(rawValue: status) ?? .pending }
        set { status = newValue.rawValue }
    }

    @Transient
    var taskPriority: TaskPriority {
        get { TaskPriority(rawValue: priority) ?? .medium }
        set { priority = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        title: String,
        category: String,
        estimatedMinutes: Int,
        priority: String = "medium",
        aiRecommended: Bool = false,
        recommendationReason: String? = nil,
        pool: String = "idea_pool",
        sortOrder: Int = 0,
        status: String = "pending",
        date: Date = .now,
        createdDate: Date = .now,
        attempted: Bool = false
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.estimatedMinutes = estimatedMinutes
        self.priority = priority
        self.aiRecommended = aiRecommended
        self.recommendationReason = recommendationReason
        self.pool = pool
        self.sortOrder = sortOrder
        self.status = status
        self.date = date
        self.createdDate = createdDate
        self.attempted = attempted
    }
}
