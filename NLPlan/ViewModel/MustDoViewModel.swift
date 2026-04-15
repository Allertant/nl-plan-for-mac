import Foundation
import SwiftData

/// 必做项 ViewModel
@Observable
final class MustDoViewModel {

    var tasks: [TaskEntity] = []
    var errorMessage: String?

    /// 移回想法池后的回调（用于通知想法池刷新）
    var onDemotedToIdeaPool: (() async -> Void)?

    private let taskManager: TaskManager

    init(taskManager: TaskManager) {
        self.taskManager = taskManager
    }

    /// 刷新必做项列表
    func refresh() async {
        do {
            tasks = try await taskManager.fetchMustDo()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 开始执行任务
    func startTask(taskId: UUID) async {
        do {
            try await taskManager.startTask(taskId: taskId)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 标记完成
    func markComplete(taskId: UUID) async {
        do {
            try await taskManager.markComplete(taskId: taskId)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 移回想法池
    func demoteToIdeaPool(taskId: UUID) async {
        do {
            try await taskManager.demoteToIdeaPool(taskId: taskId)
            await refresh()
            await onDemotedToIdeaPool?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 已完成的任务
    var completedTasks: [TaskEntity] {
        tasks.filter { $0.status == TaskStatus.done.rawValue }
    }

    /// 未完成的任务
    var pendingTasks: [TaskEntity] {
        tasks.filter { $0.status != TaskStatus.done.rawValue }
    }

    /// 正在运行的任务
    var runningTask: TaskEntity? {
        tasks.first { $0.status == TaskStatus.running.rawValue }
    }
}
