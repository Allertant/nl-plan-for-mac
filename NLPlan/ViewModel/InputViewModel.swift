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

    /// AI 解析结果，待用户确认
    var pendingParsedTasks: [ParsedTask]?

    /// 原始输入文本（确认时用于传递）
    private var pendingRawText: String = ""

    private let taskManager: TaskManager

    /// 提交成功后的回调，传入新增任务 ID（用于通知想法池刷新并高亮）
    var onSubmitSuccess: (([UUID]) async -> Void)?

    init(taskManager: TaskManager) {
        self.taskManager = taskManager
    }

    /// 提交输入 → AI 解析 → 等待用户确认
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
        pendingRawText = trimmed
        isProcessing = true
        errorMessage = nil
        successMessage = nil
        pendingParsedTasks = nil

        // 3. 仅调用 AI 解析，不保存任务
        do {
            let existingTasks = try await taskManager.fetchIdeaPool()
            let existingTitles = existingTasks.map { $0.title }
            let parsedTasks = try await taskManager.parseThoughts(
                rawText: trimmed,
                existingTaskTitles: existingTitles
            )
            pendingParsedTasks = parsedTasks
        } catch {
            errorMessage = error.localizedDescription
        }

        isProcessing = false
    }

    /// 用户确认 → 将解析结果保存到想法池
    func confirm() async {
        guard let parsedTasks = pendingParsedTasks else { return }

        do {
            let createdTasks = try await taskManager.saveParsedTasks(
                parsedTasks: parsedTasks,
                rawText: pendingRawText
            )
            successMessage = "✅ 已添加到想法池"
            let taskIds = createdTasks.map { $0.id }
            await onSubmitSuccess?(taskIds)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        // 恢复状态
        pendingParsedTasks = nil
        submittedText = ""
        inputText = ""
    }

    /// 用户取消 → 放弃解析结果，恢复输入状态
    func cancelConfirmation() {
        pendingParsedTasks = nil
        submittedText = ""
        inputText = ""
    }
}
