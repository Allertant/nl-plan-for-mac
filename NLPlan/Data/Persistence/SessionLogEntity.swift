import Foundation
import SwiftData

/// 计时记录实体
@Model
final class SessionLogEntity {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var durationSeconds: Int
    var date: Date  // 记录所属日期

    var task: TaskEntity?

    /// 计算当前仍在进行中的 session 的实时已用秒数
    @Transient
    var liveElapsedSeconds: Int {
        if endedAt != nil {
            return durationSeconds
        } else {
            return durationSeconds + Int(Date.now.timeIntervalSince(startedAt))
        }
    }

    init(
        id: UUID = UUID(),
        startedAt: Date = .now,
        endedAt: Date? = nil,
        durationSeconds: Int = 0,
        date: Date = .now,
        task: TaskEntity? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.date = date
        self.task = task
    }
}
