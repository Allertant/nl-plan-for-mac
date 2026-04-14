import Foundation
import SwiftData

/// 计时记录数据操作仓库
final class SessionLogRepository {

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func create(
        taskId: UUID,
        startedAt: Date = .now,
        date: Date = .now
    ) throws -> SessionLogEntity {
        let log = SessionLogEntity(
            startedAt: startedAt,
            date: date
        )
        // 关联 task
        let taskDescriptor = FetchDescriptor<TaskEntity>(
            predicate: #Predicate { $0.id == taskId }
        )
        if let task = try modelContext.fetch(taskDescriptor).first {
            log.task = task
        }
        modelContext.insert(log)
        try modelContext.save()
        return log
    }

    func endSession(_ log: SessionLogEntity, endedAt: Date = .now) throws {
        log.endedAt = endedAt
        log.durationSeconds = Int(endedAt.timeIntervalSince(log.startedAt))
        try modelContext.save()
    }

    func fetchLogs(taskId: UUID) throws -> [SessionLogEntity] {
        let descriptor = FetchDescriptor<SessionLogEntity>(
            predicate: #Predicate { $0.task?.id == taskId }
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchOpenSession(taskId: UUID) throws -> SessionLogEntity? {
        let descriptor = FetchDescriptor<SessionLogEntity>(
            predicate: #Predicate { log in
                log.task?.id == taskId && log.endedAt == nil
            }
        )
        return try modelContext.fetch(descriptor).first
    }
}
