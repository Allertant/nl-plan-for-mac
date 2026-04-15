import Foundation
import SwiftData

/// 想法池 ViewModel
@Observable
final class IdeaPoolViewModel {

    var tasks: [TaskEntity] = []
    var isExpanded: Bool = false
    var errorMessage: String?
    var newlyAddedTaskIds: Set<UUID> = []

    private let taskManager: TaskManager

    init(taskManager: TaskManager) {
        self.taskManager = taskManager
    }

    /// 刷新想法池（可传入新增任务 ID 用于高亮闪烁）
    func refresh(newTaskIds: Set<UUID> = []) async {
        do {
            tasks = try await taskManager.fetchIdeaPool()
            if !newTaskIds.isEmpty {
                newlyAddedTaskIds = newTaskIds
                // 2 秒后清除高亮
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(2))
                    self?.newlyAddedTaskIds.removeAll()
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 加入必做项
    func promoteToMustDo(taskId: UUID) async {
        do {
            try await taskManager.promoteToMustDo(taskId: taskId)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 删除任务
    func deleteTask(taskId: UUID) async {
        do {
            try await taskManager.deleteFromIdeaPool(taskId: taskId)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
