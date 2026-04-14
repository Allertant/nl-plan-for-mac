import Foundation
import SwiftData

/// 想法池 ViewModel
@Observable
final class IdeaPoolViewModel {

    var tasks: [TaskEntity] = []
    var isExpanded: Bool = false
    var errorMessage: String?

    private let taskManager: TaskManager

    init(taskManager: TaskManager) {
        self.taskManager = taskManager
    }

    /// 刷新想法池
    func refresh() async {
        do {
            tasks = try await taskManager.fetchIdeaPool()
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
