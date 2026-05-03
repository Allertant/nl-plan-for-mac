import SwiftUI

/// 必做项列表区域
struct MustDoSection: View {
    @Bindable var viewModel: MustDoViewModel
    let ideaPoolIdeas: [IdeaEntity]
    let projects: [ProjectEntity]

    var body: some View {
        VStack(spacing: 4) {
            mustDoListContent
        }
    }

    private var mustDoListContent: some View {
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
                            projects: projects,
                            elapsedSeconds: viewModel.elapsedSecondsCache[task.id] ?? 0,
                            onStart: { Task { await viewModel.startTask(taskId: task.id) } },
                            onPause: { Task { await viewModel.pauseTask(taskId: task.id) } },
                            onResume: { Task { await viewModel.resumeTask(taskId: task.id) } },
                            onComplete: { viewModel.requestConfirm(.complete(task.id)) },
                            onDemote: { viewModel.requestConfirm(.demote(task.id)) },
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
                AIRecommendPanel(viewModel: viewModel, ideaPoolIdeas: ideaPoolIdeas, projects: projects)
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

// MARK: - Confirm Action Page

struct ConfirmActionPage: View {
    let icon: String
    let iconTint: Color
    let title: String
    let message: String
    let confirmLabel: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(iconTint)

            Text(title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Button("取消") {
                    onCancel()
                }
                .font(.system(size: 12))
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(confirmLabel) {
                    onConfirm()
                }
                .font(.system(size: 12))
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
}

// MARK: - MustDoSection Extension

private extension MustDoViewModel.ConfirmAction {
    var isComplete: Bool {
        if case .complete = self { return true }
        return false
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
    let projects: [ProjectEntity]

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
                            viewModel: viewModel,
                            task: rec,
                            reason: rec.reason,
                            isAccepted: viewModel.acceptedRecommendationIds.contains(rec.id),
                            canEditCategory: viewModel.recommendationStrategy == .suggest,
                            canEditMinutes: true,
                            ideaPoolIdeas: ideaPoolIdeas,
                            projects: projects,
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
    @Bindable var viewModel: MustDoViewModel
    let task: TaskRecommendation
    let reason: String
    let isAccepted: Bool
    let canEditCategory: Bool
    let canEditMinutes: Bool
    let ideaPoolIdeas: [IdeaEntity]
    let projects: [ProjectEntity]
    @Binding var selectedPriority: TaskPriority
    let onAccept: () -> Void

    @State private var showingCategoryMenu = false
    @State private var editingMinutes = false
    @State private var draftMinutes = ""
    @FocusState private var focusedField: Field?

    private enum Field { case minutes }

    private var currentCategory: String {
        viewModel.editedCategories[task.id] ?? task.category
    }

    private var currentMinutes: Int {
        viewModel.editedEstimatedMinutes[task.id] ?? task.estimatedMinutes
    }

    private var sourceIdea: IdeaEntity? {
        guard let sourceIdeaId = task.sourceIdeaId else { return nil }
        return ideaPoolIdeas.first(where: { $0.id == sourceIdeaId })
    }

    private var sourceProject: ProjectEntity? {
        guard let sourceProjectId = task.sourceProjectId else { return nil }
        return projects.first(where: { $0.id == sourceProjectId })
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(task.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isAccepted ? .gray : .primary)
                        .strikethrough(isAccepted)
                        .fixedSize(horizontal: false, vertical: true)

                    if isAccepted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.green)
                    }

                    if let sourceIdea {
                        Menu {
                            Text("想法：\(sourceIdea.title)")
                        } label: {
                            Image(systemName: "link")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                    } else if let sourceProject {
                        Menu {
                            Text("项目：\(sourceProject.title)")
                        } label: {
                            Image(systemName: "link")
                                .font(.system(size: 11))
                                .foregroundStyle(.indigo)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                    }
                }

                Text(reason)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    if !isAccepted && canEditCategory {
                        Button { showingCategoryMenu.toggle() } label: {
                            TagChip(text: currentCategory)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showingCategoryMenu, attachmentAnchor: .point(.bottom), arrowEdge: .top) {
                            CategoryPickerMenu(currentCategory: currentCategory) { tag in
                                showingCategoryMenu = false
                                if tag != task.category || viewModel.editedCategories[task.id] != nil {
                                    viewModel.editedCategories[task.id] = tag
                                }
                            }
                        }
                    } else {
                        Label(currentCategory, systemImage: "tag")
                            .font(.system(size: 10))
                            .foregroundStyle(currentCategory.tagColor)
                    }

                    if !isAccepted && canEditMinutes && editingMinutes {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                            TextField("1h30m", text: $draftMinutes)
                                .textFieldStyle(.plain)
                                .frame(width: 52)
                                .focused($focusedField, equals: .minutes)
                                .onSubmit { commitMinutesEdit() }
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(3)
                    } else {
                        Label((canEditMinutes ? currentMinutes : task.estimatedMinutes).hourMinuteString, systemImage: "clock")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .onTapGesture {
                                guard !isAccepted && canEditMinutes else { return }
                                startEditingMinutes()
                            }
                    }

                    // 优先级选择
                    if !isAccepted {
                        Menu {
                            ForEach(TaskPriority.allCases, id: \.self) { p in
                                Button {
                                    selectedPriority = p
                                } label: {
                                    Label(p.displayName, systemImage: p.iconName)
                                }
                            }
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: selectedPriority.iconName)
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
        .contentShape(Rectangle())
        .onTapGesture { focusedField = nil }
        .cornerRadius(6)
        .onChange(of: focusedField) { _, newValue in
            if newValue == nil && editingMinutes { commitMinutesEdit() }
        }
    }

    private var priorityColor: Color {
        switch selectedPriority.colorName {
        case "red": return .red
        case "orange": return .orange
        case "blue": return .blue
        default: return .secondary
        }
    }

    private func startEditingMinutes() {
        draftMinutes = currentMinutes.hourMinuteString
        editingMinutes = true
        focusedField = .minutes
        CursorHelper.moveInsertionPointToEnd()
    }

    private func commitMinutesEdit() {
        editingMinutes = false
        let trimmed = draftMinutes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let minutes = trimmed.parsedHourMinuteDuration else { return }
        guard minutes != currentMinutes else { return }
        viewModel.editedEstimatedMinutes[task.id] = minutes
    }
}
struct MustDoTaskRow: View {
    let task: DailyTaskEntity
    let ideaPoolIdeas: [IdeaEntity]
    let projects: [ProjectEntity]
    var elapsedSeconds: Int = 0
    let onStart: () -> Void
    let onPause: () -> Void
    let onResume: () -> Void
    let onComplete: () -> Void
    let onDemote: () -> Void
    var onUpdateNote: ((String) -> Void)? = nil

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

    private var sourceProject: ProjectEntity? {
        guard let sourceProjectId = task.sourceProjectId else { return nil }
        return projects.first(where: { $0.id == sourceProjectId })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 行 1：状态图标 + 标题 + 计时器
            HStack(spacing: 4) {
                statusIcon

                Text(task.title)
                    .font(.system(size: 12, weight: .medium))
                    .layoutPriority(1)

                Spacer(minLength: 4)

                if isRunning || task.taskStatus == .paused {
                    RunningTimerView(initialSeconds: task.liveElapsedSeconds, isPaused: task.taskStatus == .paused)
                        .fixedSize()
                }
            }

            // 行 2：标签 + 时长 + 操作按钮
            HStack(spacing: 8) {
                taskInfoLineContent

                Spacer(minLength: 8)

                    actionButtons
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
            Image(systemName: task.taskPriority.iconName)
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

    private var actionButtons: some View {
        HStack(spacing: 4) {
            if isRunning {
                HoverIconButton(icon: "pause.fill", color: .orange, action: onPause)
                    .help("暂停")
            } else if task.taskStatus == .paused {
                HoverIconButton(icon: "play.fill", color: .green, action: onResume)
                    .help("继续")
            } else {
                HoverIconButton(icon: "play.fill", color: .green, action: onStart)
                    .help("开始执行")
            }

            HoverIconButton(icon: "checkmark", color: .blue, action: onComplete)
                .help("标记完成")

            HoverIconButton(icon: "arrow.uturn.backward", iconSize: 11, action: onDemote)
                .help("移回想法池")

            if let sourceIdea {
                Menu {
                    Text("想法：\(sourceIdea.title)")
                } label: {
                    Image(systemName: "link")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            } else if let sourceProject {
                Menu {
                    Text("项目：\(sourceProject.title)")
                } label: {
                    Image(systemName: "link")
                        .font(.system(size: 11))
                        .foregroundStyle(.indigo)
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
                TextField("添加备注...", text: $draftNote, axis: .vertical)
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
