import Foundation

/// 输入区 ViewModel（队列模式）
@Observable
final class InputViewModel {

    var inputText: String = ""
    var errorMessage: String?
    var successMessage: String?

    /// 解析队列（从 SwiftData 加载）
    var queueItems: [ParseQueueItemEntity] = []

    /// 当前正在查看详情的队列项 ID
    var activeDetailItemID: UUID?

    /// 对话输入（详情页用）
    var chatInput: String = ""

    private let taskManager: TaskManager
    private let parseQueueRepo: ParseQueueRepository

    /// 提交成功后的回调，传入新增任务 ID（用于通知想法池刷新并高亮）
    var onSubmitSuccess: (([UUID]) async -> Void)?

    init(taskManager: TaskManager, parseQueueRepo: ParseQueueRepository) {
        self.taskManager = taskManager
        self.parseQueueRepo = parseQueueRepo
    }

    // MARK: - 加载

    /// 从 SwiftData 恢复队列
    func loadQueue() {
        do {
            queueItems = try parseQueueRepo.fetchAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 应用重启后恢复队列处理（将残留的 processing 重置为 waiting）
    func resumeQueueProcessing() async {
        let stuckItems = queueItems.filter { $0.parseStatus == .processing || $0.parseStatus == .waiting }
        for item in stuckItems where item.parseStatus == .processing {
            item.parseStatus = .waiting
            try? parseQueueRepo.update(item)
        }
        if !stuckItems.isEmpty {
            await processNextInQueue()
        }
    }

    // MARK: - 提交

    /// 提交输入 → 入队 → 持久化 → 触发串行处理
    func submit() async {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "请输入内容后再提交"
            return
        }
        guard trimmed.count <= AppConstants.maxInputLength else {
            errorMessage = "输入内容不能超过 \(AppConstants.maxInputLength) 个字符"
            return
        }

        // 入队并持久化
        do {
            let item = try parseQueueRepo.create(rawText: trimmed)
            queueItems.append(item)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        inputText = ""
        errorMessage = nil

        // 触发串行处理
        await processNextInQueue()
    }

    // MARK: - 串行处理

    /// 串行处理队列中下一个 waiting 项
    private func processNextInQueue() async {
        // 已有正在处理的项则跳过
        guard !queueItems.contains(where: { $0.parseStatus == .processing }) else { return }

        // 取第一个 waiting 项
        guard let item = queueItems.first(where: { $0.parseStatus == .waiting }) else { return }

        item.parseStatus = .processing

        do {
            let existingTasks = try await taskManager.fetchIdeaPool()
            let existingTitles = existingTasks.map { $0.title }
            let parsedTasks = try await taskManager.parseThoughts(
                rawText: item.rawText,
                existingTaskTitles: existingTitles
            )
            item.parsedTasks = try await classifyParsedTasksIfNeeded(parsedTasks, force: true)
            item.parseStatus = .completed
        } catch {
            item.errorMessage = error.localizedDescription
            item.parseStatus = .failed
        }

        // 持久化状态变更
        try? parseQueueRepo.update(item)

        // 递归处理下一个
        await processNextInQueue()
    }

    // MARK: - 队列操作

    /// 确认队列项 → 保存到想法池 → 删除队列实体
    func confirmQueueItem(id: UUID) async {
        guard let index = queueItems.firstIndex(where: { $0.id == id }) else { return }
        let item = queueItems[index]
        guard let parsedTasks = item.parsedTasks else { return }

        do {
            let finalParsedTasks = try await classifyParsedTasksIfNeeded(parsedTasks)
            let createdTasks = try await taskManager.saveParsedTasks(
                parsedTasks: finalParsedTasks,
                rawText: item.rawText
            )
            successMessage = "✅ 已添加到想法池"
            let taskIds = createdTasks.map { $0.id }
            await onSubmitSuccess?(taskIds)

            // 删除队列实体
            try parseQueueRepo.delete(item)
            queueItems.remove(at: index)
        } catch {
            item.errorMessage = error.localizedDescription
        }
    }

    /// 取消队列项 → 删除实体
    func cancelQueueItem(id: UUID) {
        guard let index = queueItems.firstIndex(where: { $0.id == id }) else { return }
        let item = queueItems[index]
        // 处理中的不能取消，等它完成后再移除
        guard item.parseStatus != .processing else { return }

        do {
            try parseQueueRepo.delete(item)
            queueItems.remove(at: index)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 重试失败的队列项
    func retryQueueItem(id: UUID) async {
        guard let item = queueItems.first(where: { $0.id == id }) else { return }
        guard item.parseStatus == .failed else { return }
        item.parseStatus = .waiting
        item.errorMessage = nil
        try? parseQueueRepo.update(item)
        await processNextInQueue()
    }

    // MARK: - 详情页操作

    /// 编辑队列项中的某个任务
    func updateParsedTask(queueItemID: UUID, taskIndex: Int, title: String, category: String, estimatedMinutes: Int) {
        guard let item = queueItems.first(where: { $0.id == queueItemID }),
              var tasks = item.parsedTasks,
              taskIndex >= 0, taskIndex < tasks.count else { return }
        tasks[taskIndex].title = title
        tasks[taskIndex].category = category
        tasks[taskIndex].estimatedMinutes = estimatedMinutes
        item.parsedTasks = tasks
        try? parseQueueRepo.update(item)
    }

    /// 删除队列项中的某个任务
    func removeParsedTask(queueItemID: UUID, taskIndex: Int) {
        guard let item = queueItems.first(where: { $0.id == queueItemID }),
              var tasks = item.parsedTasks,
              taskIndex >= 0, taskIndex < tasks.count else { return }
        tasks.remove(at: taskIndex)
        item.parsedTasks = tasks
        try? parseQueueRepo.update(item)
    }

    /// 与 AI 对话修改队列项的解析结果
    func sendModification(queueItemID: UUID) async {
        guard let item = queueItems.first(where: { $0.id == queueItemID }),
              let currentTasks = item.parsedTasks else { return }

        let instruction = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { return }

        // 锁定编辑状态
        activeDetailItemID = item.id
        chatInput = ""
        errorMessage = nil

        do {
            let newTasks = try await taskManager.refineParsedTasks(
                originalInput: item.rawText,
                currentTasks: currentTasks,
                userInstruction: instruction
            )
            item.parsedTasks = try await classifyParsedTasksIfNeeded(newTasks, force: true)
            try? parseQueueRepo.update(item)
            successMessage = "✅ 已调整"
        } catch {
            errorMessage = error.localizedDescription
        }

        activeDetailItemID = nil
    }

    /// 判断指定队列项是否正在 AI 调整中
    func isItemChatProcessing(id: UUID) -> Bool {
        activeDetailItemID == id
    }

    // MARK: - Private

    private func classifyParsedTasksIfNeeded(
        _ tasks: [ParsedTask],
        force: Bool = false
    ) async throws -> [ParsedTask] {
        guard !tasks.isEmpty else { return tasks }
        if !force && tasks.allSatisfy({ $0.isProject != nil }) {
            return tasks
        }

        let inputs = tasks.map {
            ProjectClassificationInput(
                id: $0.id,
                title: $0.title,
                category: $0.category,
                estimatedMinutes: $0.estimatedMinutes
            )
        }
        let classifications = try await taskManager.classifyProjects(tasks: inputs)
        let classificationMap = Dictionary(uniqueKeysWithValues: classifications.map { ($0.ideaId, $0) })

        return tasks.map { task in
            var updated = task
            if let classification = classificationMap[task.id] {
                updated.isProject = classification.isProject
            }
            return updated
        }
    }
}
