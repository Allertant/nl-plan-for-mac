import Foundation

/// 计时引擎 — 管理任务的正计时
actor TimerEngine {

    // MARK: - State

    /// 当前正在计时的任务 ID
    private var activeTaskIds: Set<UUID> = []

    /// 计时开始时间记录
    private var startTimes: [UUID: Date] = [:]

    /// 是否允许并行计时
    private var allowParallel: Bool = false

    // MARK: - Configuration

    func setAllowParallel(_ value: Bool) {
        allowParallel = value
    }

    // MARK: - Timer Control

    /// 开始执行任务（如果并行关闭，先停止当前任务）
    /// - Returns: 被停止任务的信息 (taskId, startedAt)（如有）
    func startTask(_ taskId: UUID) -> [(taskId: UUID, startedAt: Date)] {
        var stopped: [(taskId: UUID, startedAt: Date)] = []

        if !allowParallel {
            for activeId in activeTaskIds {
                if let startTime = startTimes[activeId] {
                    stopped.append((taskId: activeId, startedAt: startTime))
                }
                activeTaskIds.remove(activeId)
                startTimes.removeValue(forKey: activeId)
            }
        }

        startTimes[taskId] = Date.now
        activeTaskIds.insert(taskId)

        return stopped
    }

    /// 停止指定任务，返回开始时间
    func stopTask(_ taskId: UUID) -> (taskId: UUID, startedAt: Date)? {
        guard activeTaskIds.contains(taskId),
              let startTime = startTimes[taskId] else {
            return nil
        }
        activeTaskIds.remove(taskId)
        startTimes.removeValue(forKey: taskId)
        return (taskId: taskId, startedAt: startTime)
    }

    /// 停止所有运行中任务
    func stopAll() -> [(taskId: UUID, startedAt: Date)] {
        var results: [(taskId: UUID, startedAt: Date)] = []
        for taskId in activeTaskIds {
            if let startTime = startTimes[taskId] {
                results.append((taskId: taskId, startedAt: startTime))
            }
        }
        activeTaskIds.removeAll()
        startTimes.removeAll()
        return results
    }

    // MARK: - Query

    /// 获取指定任务当前已计时的总秒数
    func elapsedSeconds(for taskId: UUID) -> Int {
        guard let startTime = startTimes[taskId] else { return 0 }
        return Int(Date.now.timeIntervalSince(startTime))
    }

    /// 获取当前活跃任务列表
    func activeTasks() -> [UUID] {
        Array(activeTaskIds)
    }

    /// 是否有活跃任务
    func hasActiveTasks() -> Bool {
        !activeTaskIds.isEmpty
    }

    /// 获取当前计时显示文本（如 "00:32:15"）
    func timerDisplay(for taskId: UUID) -> String {
        let seconds = elapsedSeconds(for: taskId)
        return formatDuration(seconds: seconds)
    }

    /// 获取当前第一个活跃任务的计时显示
    func primaryTimerDisplay() -> String {
        guard let firstId = activeTaskIds.first,
              let startTime = startTimes[firstId] else {
            return ""
        }
        let seconds = Int(Date.now.timeIntervalSince(startTime))
        return formatDuration(seconds: seconds)
    }

    // MARK: - Helper

    private func formatDuration(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }
}
