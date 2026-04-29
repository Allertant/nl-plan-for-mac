import Foundation

/// 计时引擎 — 管理并行控制，计时状态持久化在 DailyTaskEntity
actor TimerEngine {

    // MARK: - State

    /// 是否允许并行计时
    private var allowParallel: Bool = false

    // MARK: - Configuration

    func setAllowParallel(_ value: Bool) {
        allowParallel = value
    }

    func getAllowParallel() -> Bool {
        allowParallel
    }

    // MARK: - Parallel Control

    /// 判断是否允许启动新任务（由 TaskManager 调用）
    /// 返回需要暂停的正在运行的任务 ID 列表
    func tasksToPauseBeforeStart(runningTaskIds: [UUID], newTaskId: UUID) -> [UUID] {
        if allowParallel {
            // 允许并行，只需暂停正在运行的同一个任务（如果存在）
            return runningTaskIds.filter { $0 == newTaskId }
        }
        // 不允许并行，暂停所有正在运行的任务
        return runningTaskIds
    }
}
