import Foundation
import SwiftData

/// 想法池 ViewModel
@Observable
final class IdeaPoolViewModel {

    var tasks: [TaskEntity] = []
    var isExpanded: Bool = false
    var errorMessage: String?
    var newlyAddedTaskIds: Set<UUID> = []

    /// 提升到必做项后的回调（用于通知必做项刷新）
    var onPromotedToMustDo: (() async -> Void)?

    // MARK: - 清理状态

    enum CleanupState: Equatable {
        case idle
        case loading
        case loaded(CleanupResult)
        case error(String)
    }

    var cleanupState: CleanupState = .idle

    /// 已确认删除的 taskId
    var confirmedCleanupIds: Set<UUID> = []

    /// 撤销栈（按顺序记录已标记删除的 taskId）
    private var undoStack: [UUID] = []

    /// 是否可以撤销
    var canUndoCleanup: Bool { !undoStack.isEmpty }

    var showCleanupPanel: Bool {
        switch cleanupState {
        case .loading, .loaded, .error: return true
        case .idle: return false
        }
    }

    var currentCleanupResult: CleanupResult? {
        if case .loaded(let result) = cleanupState { return result }
        return nil
    }

    var allCleanupConfirmed: Bool {
        guard let result = currentCleanupResult else { return false }
        return result.items.allSatisfy { confirmedCleanupIds.contains($0.taskId) }
    }

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
    func promoteToMustDo(taskId: UUID, priority: TaskPriority = .medium) async {
        do {
            try await taskManager.promoteToMustDo(taskId: taskId, priority: priority)
            await refresh()
            await onPromotedToMustDo?()
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

    /// 更新任务字段（标题/标签/时长/备注）
    func updateTask(taskId: UUID, title: String? = nil, category: String? = nil, estimatedMinutes: Int? = nil, note: String? = nil) async {
        do {
            if let task = try await taskManager.fetchIdeaPoolTask(taskId: taskId) {
                if let title { task.title = title }
                if let category { task.category = category }
                if let estimatedMinutes { task.estimatedMinutes = estimatedMinutes }
                if let note { task.note = note }
                try await taskManager.updateTask(task)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - AI 清理

    /// 请求 AI 分析可清理的任务
    func fetchCleanupSuggestions() async {
        cleanupState = .loading
        errorMessage = nil
        confirmedCleanupIds = []
        undoStack = []

        let inputs = tasks.map { task in
            TaskRecommendationInput(
                id: task.id,
                title: task.title,
                category: task.category,
                estimatedMinutes: task.estimatedMinutes,
                attempted: task.attempted,
                status: task.status
            )
        }

        do {
            let aiService = await makeAIService()
            let result = try await aiService.cleanupIdeaPool(tasks: inputs)

            // 过滤掉不存在的 taskId
            let taskIds = Set(tasks.map { $0.id })
            let validItems = result.items.filter { taskIds.contains($0.taskId) }
            let filteredResult = CleanupResult(items: validItems, overallReason: result.overallReason)

            cleanupState = .loaded(filteredResult)
        } catch {
            cleanupState = .error(error.localizedDescription)
        }
    }

    /// 标记单条为待删除（不执行数据库操作）
    func markCleanupItem(taskId: UUID) {
        confirmedCleanupIds.insert(taskId)
        undoStack.append(taskId)
    }

    /// 标记所有为待删除
    func markAllCleanupItems() {
        guard let result = currentCleanupResult else { return }
        for item in result.items where !confirmedCleanupIds.contains(item.taskId) {
            confirmedCleanupIds.insert(item.taskId)
            undoStack.append(item.taskId)
        }
    }

    /// 撤销上一次标记
    func undoLastCleanup() {
        guard let lastId = undoStack.popLast() else { return }
        confirmedCleanupIds.remove(lastId)
    }

    /// 执行批量删除（从数据库真正删除所有已标记项）
    func executeCleanup() async {
        for taskId in confirmedCleanupIds {
            do {
                try await taskManager.deleteFromIdeaPool(taskId: taskId)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        await refresh()
        resetCleanupState()
    }

    /// 跳过单条（从建议列表中移除，不删除）
    func skipCleanupItem(taskId: UUID) {
        guard case .loaded(let result) = cleanupState else { return }
        let updated = result.items.filter { $0.taskId != taskId }
        cleanupState = .loaded(CleanupResult(items: updated, overallReason: result.overallReason))
    }

    /// 重置清理状态（全部跳过时调用）
    func resetCleanupState() {
        cleanupState = .idle
        confirmedCleanupIds = []
        undoStack = []
    }

    // MARK: - Private

    private func makeAIService() async -> AIServiceProtocol {
        let apiKey = KeychainStore.shared.load(key: AppConstants.apiKeyKeychainKey) ?? ""
        let model = UserDefaults.standard.string(forKey: AppConstants.selectedModelKey) ?? AppConstants.defaultModel
        return DeepSeekAIService(apiKey: apiKey, model: model)
    }
}
