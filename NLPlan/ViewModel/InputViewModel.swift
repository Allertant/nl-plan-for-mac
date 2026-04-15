import Foundation
import SwiftData

/// 输入区 ViewModel
@Observable
final class InputViewModel {

    var inputText: String = ""
    var submittedText: String = ""
    var isProcessing: Bool = false
    var errorMessage: String?
    var successMessage: String?

    private let taskManager: TaskManager

    /// 提交成功后的回调，传入新增任务 ID（用于通知想法池刷新并高亮）
    var onSubmitSuccess: (([UUID]) async -> Void)?

    init(taskManager: TaskManager) {
        self.taskManager = taskManager
    }

    func submit() async {
        // 1. 验证
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "请输入内容后再提交"
            return
        }
        guard trimmed.count <= AppConstants.maxInputLength else {
            errorMessage = "输入内容不能超过 \(AppConstants.maxInputLength) 个字符"
            return
        }

        // 2. 锁定提交文本
        submittedText = trimmed
        isProcessing = true
        errorMessage = nil
        successMessage = nil

        // 3. 调用 Domain
        do {
            let createdTasks = try await taskManager.submitThought(rawText: trimmed)
            successMessage = "✅ 解析成功"
            let taskIds = createdTasks.map { $0.id }
            await onSubmitSuccess?(taskIds)
        } catch {
            errorMessage = error.localizedDescription
        }

        // 4. 恢复状态
        submittedText = ""
        inputText = ""
        isProcessing = false
    }
}
