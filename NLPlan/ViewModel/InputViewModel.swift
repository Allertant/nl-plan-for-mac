import Foundation
import SwiftData

/// 输入区 ViewModel
@Observable
final class InputViewModel {

    var inputText: String = ""
    var isProcessing: Bool = false
    var errorMessage: String?

    private let taskManager: TaskManager

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

        // 2. 状态更新
        isProcessing = true
        errorMessage = nil

        // 3. 调用 Domain
        do {
            _ = try await taskManager.submitThought(rawText: trimmed)
            inputText = ""
        } catch {
            errorMessage = error.localizedDescription
        }

        // 4. 恢复状态
        isProcessing = false
    }
}
