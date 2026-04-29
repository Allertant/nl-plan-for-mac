import SwiftUI

/// 必做项列表区域
struct MustDoSection: View {
    @Bindable var viewModel: MustDoViewModel
    let ideaPoolIdeas: [IdeaEntity]
    let timerEngine: TimerEngine

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("必做项")
                    .font(.system(size: 13, weight: .semibold))
                if !viewModel.tasks.isEmpty {
                    Text("\(viewModel.completedTasks.count)/\(viewModel.tasks.count)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()

                if !viewModel.pendingTasks.isEmpty && !viewModel.isEditMode {
                    Button {
                        viewModel.isEditMode = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("排序")
                }

                if viewModel.isEditMode {
                    Button("完成") {
                        viewModel.isEditMode = false
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if viewModel.tasks.isEmpty {
                Text("还没有必做项")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 16)
            } else {
                // 未完成任务
                LazyVStack(spacing: 4) {
                    ForEach(Array(viewModel.pendingTasks.enumerated()), id: \.element.id) { index, task in
                        MustDoTaskRow(
                            task: task,
                            ideaPoolIdeas: ideaPoolIdeas,
                            elapsedSeconds: viewModel.elapsedSecondsCache[task.id] ?? 0,
                            isEditMode: viewModel.isEditMode,
                            canMoveUp: viewModel.canMoveUp(at: index),
                            canMoveDown: viewModel.canMoveDown(at: index),
                            timerEngine: timerEngine,
                            onStart: { Task { await viewModel.startTask(taskId: task.id) } },
                            onComplete: { Task { await viewModel.markComplete(taskId: task.id) } },
                            onDemote: { Task { await viewModel.demoteToIdeaPool(taskId: task.id) } },
                            onMoveUp: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    viewModel.moveUp(at: index)
                                }
                            },
                            onMoveDown: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    viewModel.moveDown(at: index)
                                }
                            },
                            onUpdateNote: { note in
                                Task { await viewModel.updateTaskNote(taskId: task.id, note: note) }
                            }
                        )
                    }

                    // 为底部浮动按钮留出空间
                    if !ideaPoolIdeas.isEmpty && !viewModel.showRecommendationPanel {
                        Color.clear.frame(height: 36)
                    }
                }
                .padding(.horizontal, 8)

                // 已完成任务
                if !viewModel.completedTasks.isEmpty {
                    Divider()
                        .padding(.horizontal, 12)

                    LazyVStack(spacing: 4) {
                        ForEach(viewModel.completedTasks, id: \.id) { task in
                            CompletedTaskRow(task: task, elapsedSeconds: viewModel.elapsedSecondsCache[task.id] ?? 0)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }

            // AI 推荐面板
            if viewModel.showRecommendationPanel {
                AIRecommendPanel(viewModel: viewModel, ideaPoolIdeas: ideaPoolIdeas)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
            }
        }
        .padding(8)
        .background(
            Color.green.opacity(0.06)
                .contentShape(Rectangle())
                .onTapGesture { NSApp.keyWindow?.makeFirstResponder(nil) }
        )
        .cornerRadius(8)
    }
}

// MARK: - AI 推荐面板

private func formatTokenCount(_ count: Int) -> String {
    if count >= 1000 {
        return "\(count / 1000)k"
    }
    return "\(count)"
}
private struct AIRecommendPanel: View {
    @Bindable var viewModel: MustDoViewModel
    let ideaPoolIdeas: [IdeaEntity]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 头部
            HStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.accentColor)
                Text("AI 推荐")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                if viewModel.recommendationState != .loading {
                    Button {
                        viewModel.dismissRecommendations()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            switch viewModel.recommendationState {
            case .loading:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("AI 正在分析...")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("取消") {
                        viewModel.dismissRecommendations()
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)

            case .loaded(let result):
                if result.overallReason.isEmpty == false {
                    Text(result.overallReason)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                if result.recommendations.isEmpty {
                    Text("今天没有合适的推荐项")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(result.recommendations) { rec in
                        RecommendationRow(
                            task: rec,
                            reason: rec.reason,
                            isAccepted: viewModel.acceptedRecommendationIds.contains(rec.id),
                            selectedPriority: Binding(
                                get: { viewModel.selectedPriorities[rec.id] ?? .medium },
                                set: { viewModel.selectedPriorities[rec.id] = $0 }
                            ),
                            onAccept: {
                                Task { await viewModel.acceptRecommendation(recommendationId: rec.id) }
                            }
                        )
                    }

                    // Token 用量
                    if viewModel.cumulativeTokenInput > 0 || viewModel.cumulativeTokenOutput > 0 {
                        HStack {
                            Spacer()
                            Text("输入: \(formatTokenCount(viewModel.cumulativeTokenInput)), 输出: \(formatTokenCount(viewModel.cumulativeTokenOutput))")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }

                    // 全部加入 / 完成 按钮
                    if viewModel.allRecommendationsAccepted {
                        Button {
                            viewModel.dismissRecommendations()
                        } label: {
                            Text("完成")
                                .font(.system(size: 11))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    } else {
                        Button {
                            Task { await viewModel.acceptAllRecommendations() }
                        } label: {
                            Text("全部加入必做项")
                                .font(.system(size: 11))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

            case .error(let message):
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .padding(.vertical, 8)

            case .idle:
                EmptyView()
            }
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, 8)
    }
}

// MARK: - 推荐任务行

private struct RecommendationRow: View {
    let task: TaskRecommendation
    let reason: String
    let isAccepted: Bool
    @Binding var selectedPriority: TaskPriority
    let onAccept: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(task.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isAccepted ? .gray : .primary)
                        .strikethrough(isAccepted)
                        .lineLimit(1)

                    if isAccepted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.green)
                    }
                }

                Text(reason)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Label(task.category, systemImage: "tag")
                        .font(.system(size: 10))
                        .foregroundStyle(task.category.tagColor)

                    Label(task.estimatedMinutes.hourMinuteString, systemImage: "clock")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    // 优先级选择
                    if !isAccepted {
                        Menu {
                            ForEach(TaskPriority.allCases, id: \.self) { p in
                                Button {
                                    selectedPriority = p
                                } label: {
                                    Label(p.displayName, systemImage: p == .high ? "flag.fill" : "flag")
                                }
                            }
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: priorityIcon)
                                    .font(.system(size: 9))
                                    .foregroundStyle(priorityColor)
                                Text(selectedPriority.displayName)
                                    .font(.system(size: 9))
                                    .foregroundStyle(priorityColor)
                            }
                        }
                        .menuStyle(.borderlessButton)
                    }
                }
            }

            Spacer()

            if !isAccepted {
                Button {
                    onAccept()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                .help("加入必做项")
            }
        }
        .padding(8)
        .background(
            isAccepted
            ? Color(nsColor: .textBackgroundColor).opacity(0.3)
            : Color(nsColor: .textBackgroundColor)
        )
        .cornerRadius(6)
    }

    private var priorityIcon: String {
        switch selectedPriority {
        case .high: return "flag.fill"
        case .medium: return "flag"
        case .low: return "flag"
        }
    }

    private var priorityColor: Color {
        switch selectedPriority {
        case .high: return .red
        case .medium: return .orange
        case .low: return .blue
        }
    }
}

/// 必做项任务卡片
struct MustDoTaskRow: View {
    let task: DailyTaskEntity
    let ideaPoolIdeas: [IdeaEntity]
    var elapsedSeconds: Int = 0
    var isEditMode: Bool = false
    var canMoveUp: Bool = false
    var canMoveDown: Bool = false
    let timerEngine: TimerEngine
    let onStart: () -> Void
    let onComplete: () -> Void
    let onDemote: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    var onUpdateNote: ((String) -> Void)? = nil

    @State private var showCompleteConfirm = false
    @State private var isEditingNote = false
    @State private var draftNote = ""
    @FocusState private var focusedField: NoteField?
    private enum NoteField: Hashable { case note }
    @State private var monitor: Any?

    private var isRunning: Bool { task.taskStatus == .running }
    private var sourceIdea: IdeaEntity? {
        guard let sourceIdeaId = task.sourceIdeaId else { return nil }
        return ideaPoolIdeas.first(where: { $0.id == sourceIdeaId })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 行 1：状态图标 + 标题 + 计时器
            HStack(spacing: 4) {
                statusIcon

                Text(task.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .layoutPriority(1)

                Spacer(minLength: 4)

                if isRunning {
                    RunningTimerView(taskId: task.id, timerEngine: timerEngine)
                        .fixedSize()
                }
            }

            // 行 2：标签 + 时长 + 操作按钮
            HStack(spacing: 8) {
                taskInfoLineContent

                Spacer(minLength: 8)

                if isEditMode {
                    reorderButtons
                } else {
                    actionButtons
                }
            }

            // 行 3：备注
            noteArea
        }
        .padding(8)
        .background { rowBackground.contentShape(Rectangle()).onTapGesture { focusedField = nil } }
        .cornerRadius(6)
        .overlay(rowBorder)
        .onChange(of: focusedField) { _, newValue in
            if newValue == nil, isEditingNote { commitNoteEdit() }
        }
        .onAppear {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
                if focusedField != nil {
                    focusedField = nil
                }
                return event
            }
        }
        .onDisappear {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }

    // MARK: - Subviews

    private var statusIcon: some View {
        Image(systemName: task.taskStatus.iconName)
            .font(.system(size: 16))
            .foregroundStyle(isRunning ? Color.green : Color.secondary)
    }

    private var taskInfoLineContent: some View {
        HStack(spacing: 8) {
            Image(systemName: task.taskPriority == .high ? "flag.fill" : "flag")
                .font(.system(size: 9))
                .foregroundStyle(
                    task.taskPriority == .high ? .red :
                    task.taskPriority == .medium ? .orange : .blue
                )

            TagChip(text: task.category)

            Label("预计\(task.estimatedMinutes.hourMinuteString)", systemImage: "clock")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private var reorderButtons: some View {
        HStack(spacing: 2) {
            Button(action: onMoveUp) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(canMoveUp ? Color.primary : Color.gray.opacity(0.3))
            }
            .buttonStyle(.plain)
            .disabled(!canMoveUp)

            Button(action: onMoveDown) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(canMoveDown ? Color.primary : Color.gray.opacity(0.3))
            }
            .buttonStyle(.plain)
            .disabled(!canMoveDown)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 4) {
            if !isRunning {
                Button(action: onStart) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                .help("开始执行")
            }

            Button {
                if isRunning {
                    onComplete()
                } else if showCompleteConfirm {
                    onComplete()
                } else {
                    showCompleteConfirm = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        showCompleteConfirm = false
                    }
                }
            } label: {
                Image(systemName: showCompleteConfirm ? "checkmark.circle.fill" : "checkmark")
                    .font(.system(size: 12))
                    .foregroundStyle(showCompleteConfirm ? .red : .blue)
            }
            .buttonStyle(.plain)
            .help(showCompleteConfirm ? "再次点击确认完成" : "标记完成")

            Button(action: onDemote) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("移回想法池")

            if let sourceIdea {
                Menu {
                    Text(sourceIdea.isProject ? "项目：\(sourceIdea.title)" : "想法：\(sourceIdea.title)")
                } label: {
                    Image(systemName: "link")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }
        }
    }

    private var rowBackground: Color {
        isRunning ? Color.green.opacity(0.08) : Color(nsColor: .textBackgroundColor)
    }

    private var rowBorder: some View {
        RoundedRectangle(cornerRadius: 6)
            .stroke(isRunning ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
    }

    // MARK: - Note

    private var noteArea: some View {
        Group {
            if isEditingNote {
                TextField("添加备注...", text: $draftNote)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .focused($focusedField, equals: .note)
                    .onSubmit { commitNoteEdit() }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(3)
            } else {
                Text(task.note?.isEmpty ?? true ? "添加备注..." : task.note ?? "")
                    .font(.system(size: 10))
                    .foregroundStyle((task.note?.isEmpty ?? true) ? .tertiary : .secondary)
                    .onTapGesture { startEditingNote() }
            }
        }
    }

    private func startEditingNote() {
        guard onUpdateNote != nil else { return }
        draftNote = task.note ?? ""
        isEditingNote = true
        focusedField = .note
        moveInsertionPointToEnd()
    }

    private func commitNoteEdit() {
        isEditingNote = false
        let trimmed = draftNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != (task.note ?? "") {
            onUpdateNote?(trimmed.isEmpty ? "" : trimmed)
        }
    }

    private func moveInsertionPointToEnd(retryCount: Int = 3) {
        DispatchQueue.main.async {
            guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else {
                if retryCount > 0 { self.moveInsertionPointToEnd(retryCount: retryCount - 1) }
                return
            }
            let endLocation = textView.string.count
            textView.setSelectedRange(NSRange(location: endLocation, length: 0))
        }
    }
}

/// 已完成任务卡片
struct CompletedTaskRow: View {
    let task: DailyTaskEntity
    var elapsedSeconds: Int = 0

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.gray)

            Text(task.title)
                .font(.system(size: 12))
                .foregroundStyle(.gray)
                .strikethrough()

            Spacer()

            let minutes = elapsedSeconds / 60
            Text(minutes.hourMinuteString)
                .font(.system(size: 10))
                .foregroundStyle(.gray)
        }
        .padding(8)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
        .cornerRadius(6)
    }
}

// MARK: - View Extension

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
