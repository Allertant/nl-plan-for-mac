import Foundation

/// 输入区 ViewModel（队列模式）
@MainActor @Observable
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

    /// 提交成功后的回调，传入新增想法 ID（用于通知想法池刷新并高亮）
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

    /// 串行处理队列（迭代，避免递归栈溢出）
    private func processNextInQueue() async {
        while true {
            // 已有正在处理的项则跳过
            guard !queueItems.contains(where: { $0.parseStatus == .processing }) else { return }

            // 取第一个 waiting 项
            guard let item = queueItems.first(where: { $0.parseStatus == .waiting }) else { return }

            item.parseStatus = .processing

            do {
                let existingIdeas = try await taskManager.fetchIdeaPool()
                let existingTitles = existingIdeas.map { $0.title }
                let parsedTasks = try await taskManager.parseThoughts(
                    rawText: item.rawText,
                    existingTaskTitles: existingTitles
                )
                accumulateTokenUsage(for: item.id)
                item.parsedTasks = try await classifyParsedTasksIfNeeded(parsedTasks)
                item.parseStatus = .completed
            } catch {
                item.errorMessage = error.localizedDescription
                item.parseStatus = .failed
            }

            // 持久化状态变更
            try? parseQueueRepo.update(item)
        }
    }

    // MARK: - 队列操作

    /// 确认队列项 → 保存到想法池 → 删除队列实体
    func confirmQueueItem(id: UUID) async {
        guard let index = queueItems.firstIndex(where: { $0.id == id }) else { return }
        let item = queueItems[index]
        guard let parsedTasks = item.parsedTasks else { return }

        do {
            let finalParsedTasks = try await classifyParsedTasksIfNeeded(parsedTasks)
            accumulateTokenUsage(for: id)
            let createdIds = try await taskManager.saveParsedTasks(
                parsedTasks: finalParsedTasks,
                rawText: item.rawText
            )
            successMessage = "✅ 已添加到想法池"
            await onSubmitSuccess?(createdIds)

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

    /// 编辑队列项中的某个任务（按 ID 查找，避免 index 错位）
    func updateParsedTask(queueItemID: UUID, taskID: UUID, title: String, category: String, estimatedMinutes: Int?, note: String?, deadline: Date? = nil, deadlineHasExplicitYear: Bool = false, deadlineHasTime: Bool = false) {
        guard let item = queueItems.first(where: { $0.id == queueItemID }),
              var tasks = item.parsedTasks,
              let idx = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[idx].title = title
        tasks[idx].category = category
        tasks[idx].estimatedMinutes = estimatedMinutes
        tasks[idx].note = (note?.isEmpty ?? true) ? nil : note
        tasks[idx].deadline = deadline
        tasks[idx].deadlineHasExplicitYear = deadlineHasExplicitYear
        tasks[idx].deadlineHasTime = deadlineHasTime
        item.parsedTasks = tasks
        try? parseQueueRepo.update(item)
    }

    /// 切换任务的项目/普通想法状态
    func toggleProjectState(queueItemID: UUID, taskID: UUID) {
        guard let item = queueItems.first(where: { $0.id == queueItemID }),
              var tasks = item.parsedTasks,
              let idx = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        let isProject = !(tasks[idx].isProject ?? false)
        tasks[idx].isProject = isProject
        if isProject {
            tasks[idx].estimatedMinutes = nil
        } else if tasks[idx].estimatedMinutes == nil {
            tasks[idx].estimatedMinutes = 30
        }
        item.parsedTasks = tasks
        try? parseQueueRepo.update(item)
    }

    /// 删除队列项中的某个任务（按 ID 查找）
    @discardableResult
    func removeParsedTask(queueItemID: UUID, taskID: UUID) -> Bool {
        guard let item = queueItems.first(where: { $0.id == queueItemID }),
              var tasks = item.parsedTasks,
              let idx = tasks.firstIndex(where: { $0.id == taskID }) else { return false }
        tasks.remove(at: idx)
        item.parsedTasks = tasks
        try? parseQueueRepo.update(item)

        if tasks.isEmpty {
            try? parseQueueRepo.delete(item)
            queueItems.removeAll { $0.id == queueItemID }
            return true // 表示队列项已清空
        }
        return false
    }

    /// 单个 approve：将指定任务加入想法池，从当前列表中移除（按 ID 查找）
    /// 返回 true 表示队列项已清空（需要返回主页）
    func approveSingleTask(queueItemID: UUID, taskID: UUID) async -> Bool {
        guard let item = queueItems.first(where: { $0.id == queueItemID }),
              var tasks = item.parsedTasks,
              let idx = tasks.firstIndex(where: { $0.id == taskID }) else { return false }

        let task = tasks[idx]
        do {
            let classified = try await classifyParsedTasksIfNeeded([task], force: task.isProject == nil)
            accumulateTokenUsage(for: queueItemID)
            let createdId = try await taskManager.saveSingleParsedTask(classified[0], rawText: item.rawText)
            await onSubmitSuccess?([createdId])

            tasks.remove(at: idx)
            item.parsedTasks = tasks

            if tasks.isEmpty {
                try? parseQueueRepo.delete(item)
                queueItems.removeAll { $0.id == queueItemID }
                return true
            } else {
                try? parseQueueRepo.update(item)
                successMessage = "✅ 已添加到想法池"
                return false
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// 更新队列项的原始输入文本
    func updateRawText(queueItemID: UUID, newText: String) {
        guard let item = queueItems.first(where: { $0.id == queueItemID }) else { return }
        item.rawText = newText
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
            accumulateTokenUsage(for: queueItemID)
            item.parsedTasks = try await classifyParsedTasksIfNeeded(newTasks, force: false)
            accumulateTokenUsage(for: queueItemID)
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

    private func accumulateTokenUsage(for queueItemID: UUID) {
        guard let usage = taskManager.lastTokenUsage else { return }
        guard let item = queueItems.first(where: { $0.id == queueItemID }) else { return }
        item.cumulativeInputTokens = (item.cumulativeInputTokens ?? 0) + usage.inputTokens
        item.cumulativeOutputTokens = (item.cumulativeOutputTokens ?? 0) + usage.outputTokens
        try? parseQueueRepo.update(item)
    }

    private func classifyParsedTasksIfNeeded(
        _ tasks: [ParsedTask],
        force: Bool = false
    ) async throws -> [ParsedTask] {
        guard !tasks.isEmpty else { return tasks }
        let unclassified = tasks.filter { $0.isProject == nil }
        guard force || !unclassified.isEmpty else { return tasks }

        let inputs = unclassified.map {
            ProjectClassificationInput(
                id: $0.id,
                title: $0.title,
                category: $0.category
            )
        }
        guard !inputs.isEmpty else { return tasks }
        let classifications = try await taskManager.classifyProjects(tasks: inputs)
        let classificationMap = Dictionary(uniqueKeysWithValues: classifications.map { ($0.ideaId, $0) })

        return tasks.map { task in
            guard task.isProject == nil else { return task }
            var updated = task
            if let classification = classificationMap[task.id] {
                updated.isProject = classification.isProject
                if classification.isProject {
                    updated.estimatedMinutes = nil
                } else if updated.estimatedMinutes == nil {
                    updated.estimatedMinutes = 30
                }
            }
            return updated
        }
    }
}
