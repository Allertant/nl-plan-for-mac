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
            date: date,
            taskId: taskId
        )
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
        let targetId = taskId
        let descriptor = FetchDescriptor<SessionLogEntity>(
            predicate: #Predicate { $0.taskId == targetId }
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchOpenSession(taskId: UUID) throws -> SessionLogEntity? {
        let targetId = taskId
        let descriptor = FetchDescriptor<SessionLogEntity>(
            predicate: #Predicate { log in
                log.taskId == targetId && log.endedAt == nil
            }
        )
        return try modelContext.fetch(descriptor).first
    }

    func totalElapsedSeconds(taskId: UUID) throws -> Int {
        try fetchLogs(taskId: taskId).reduce(0) { $0 + $1.durationSeconds }
    }
}
