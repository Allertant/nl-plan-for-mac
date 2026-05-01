import SwiftUI

struct ProjectDetailContainerView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if let ideaPoolVM = appState.ideaPoolViewModel,
               let projectIdeaId = appState.currentPage.projectItemID,
               let idea = ideaPoolVM.ideas.first(where: { $0.id == projectIdeaId }) {
                ProjectDetailPageView(
                    viewModel: ideaPoolVM,
                    idea: idea,
                    onDismiss: {
                        let returnTo = appState.returnPage ?? .ideaPool
                        appState.returnPage = nil
                        appState.currentPage = returnTo
                    }
                )
            } else {
                ProgressView("加载中...")
                    .frame(width: 360, height: 520)
            }
        }
    }
}

private struct ProjectDetailPageView: View {
    let viewModel: IdeaPoolViewModel
    let idea: IdeaEntity
    let onDismiss: () -> Void

    @State private var projectDetail: ProjectDetailSnapshot?
    @State private var allTasks: [DailyTaskEntity] = []
    @State private var notes: [ProjectNoteEntity] = []
    @State private var isLoading = true

    // 项目描述编辑
    @State private var isEditingDescription = false
    @State private var draftDescription = ""
    @FocusState private var descriptionFocused: Bool

    // 标题编辑
    @State private var isEditingTitle = false
    @State private var draftTitle = ""
    @FocusState private var titleFocused: Bool

    // 规划背景编辑
    @State private var isEditingPlanningBackground = false
    @State private var draftPlanningBackground = ""
    @FocusState private var planningBackgroundFocused: Bool

    // 研究提示词
    @State private var isGeneratingPlanningPrompt = false
    @State private var showCopyPromptToast = false

    // 笔记
    @State private var newNoteText = ""
    @FocusState private var newNoteFocused: Bool

    // 安排
    @State private var newArrangementText = ""
    @State private var newArrangementMinutes: Int = 30
    @State private var editingNewArrangementMinutes = false
    @State private var draftNewArrangementMinutes = ""
    @FocusState private var newArrangementFocused: Bool
    @FocusState private var newArrangementMinutesFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                BackButton(action: onDismiss).help("返回想法池")
                Image(systemName: "folder.fill").font(.system(size: 12)).foregroundStyle(.indigo)
                Text("项目详情").font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            if isLoading {
                ProgressView("加载中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let project = projectDetail {
                if viewModel.pendingArrangementId != nil {
                    arrangementConfirmPage
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            summaryCard(project)
                            descriptionCard(project)
                            planningBackgroundCard(project)
                            tasksCard
                            arrangementCard
                            noteCard
                        }
                        .padding(12)
                        .background(
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { dismissAllEditing() }
                        )
                    }
                    .scrollIndicators(.automatic)
                }
            }
        }
        .frame(width: 360, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .task { await loadProjectDetail() }
        .onChange(of: titleFocused) { _, focused in
            if !focused && isEditingTitle { commitTitleEdit() }
        }
        .onChange(of: descriptionFocused) { _, focused in
            if !focused && isEditingDescription { commitDescriptionEdit() }
        }
        .onChange(of: planningBackgroundFocused) { _, focused in
            if !focused && isEditingPlanningBackground { commitPlanningBackgroundEdit() }
        }
        .onChange(of: newArrangementMinutesFocused) { _, focused in
            if !focused && editingNewArrangementMinutes { commitNewArrangementMinutes() }
        }
    }

    private func dismissAllEditing() {
        if isEditingTitle { titleFocused = false }
        if isEditingDescription { descriptionFocused = false }
        if isEditingPlanningBackground { planningBackgroundFocused = false }
        newNoteFocused = false
        newArrangementFocused = false
        newArrangementMinutesFocused = false
    }

    // MARK: - Data

    private func loadProjectDetail() async {
        let ideaId = idea.id
        async let projectNotes = viewModel.fetchProjectNotes(ideaId: ideaId)
        async let projectArrangements = viewModel.fetchArrangements(projectId: ideaId)
        await refreshAllTasks()
        notes = await projectNotes
        _ = await projectArrangements

        if let freshIdea = await viewModel.fetchIdea(ideaId: ideaId) {
            projectDetail = ProjectDetailSnapshot(idea: freshIdea)
        }
        isLoading = false
    }

    private func reloadDetail() async {
        guard let freshIdea = await viewModel.fetchIdea(ideaId: idea.id) else { return }
        projectDetail = ProjectDetailSnapshot(idea: freshIdea)
    }

    private func refreshAllTasks() async {
        let ideaId = idea.id
        async let tasks = viewModel.fetchLinkedMustDoTasks(sourceIdeaId: ideaId)
        async let settled = viewModel.fetchSettledTasks(sourceIdeaId: ideaId)
        let active = await tasks
        let settledList = await settled
        let settledIds = Set(settledList.map(\.id))
        allTasks = active.filter { !settledIds.contains($0.id) } + settledList
    }

    // MARK: - Cards

    private func commitTitleEdit() {
        isEditingTitle = false
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != projectDetail?.title else { return }
        Task {
            await viewModel.updateIdea(ideaId: idea.id, title: trimmed)
            await reloadDetail()
        }
    }

    private func summaryCard(_ project: ProjectDetailSnapshot) -> some View {
        DetailSectionCard(title: "项目信息", systemImage: "lightbulb.fill", tint: .yellow, background: Color.yellow.opacity(0.08), border: Color.yellow.opacity(0.22)) {
            VStack(alignment: .leading, spacing: 8) {
                if isEditingTitle {
                    TextField("项目标题", text: $draftTitle, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1...3)
                        .focused($titleFocused)
                        .onSubmit { titleFocused = false }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(3)
                } else {
                    Text(project.title).font(.system(size: 15, weight: .semibold)).lineLimit(3)
                        .onTapGesture {
                            draftTitle = project.title
                            isEditingTitle = true
                            DispatchQueue.main.async { titleFocused = true }
                        }
                }
                HStack(spacing: 8) {
                    TagChip(text: project.category)
                    Text(project.createdDate.shortDateTimeString).font(.system(size: 10)).foregroundStyle(.tertiary)
                }

                if let progress = project.projectProgress {
                    Divider().padding(.vertical, 2)
                    HStack(spacing: 6) {
                        ProgressView(value: progress / 100).progressViewStyle(.linear).tint(.indigo)
                        Text("\(Int(progress))%").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    }
                }
                if let summary = project.projectProgressSummary, !summary.isEmpty {
                    if project.projectProgress == nil { Divider().padding(.vertical, 2) }
                    Text(summary).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if let updatedAt = project.projectProgressUpdatedAt {
                    Text("进度更新于 \(updatedAt.relativeTimeString)").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func descriptionCard(_ project: ProjectDetailSnapshot) -> some View {
        DetailSectionCard(title: "项目描述", systemImage: "doc.text", tint: .purple, background: Color.purple.opacity(0.08), border: Color.purple.opacity(0.22), onBackgroundTap: dismissAllEditing) {
            if isEditingDescription {
                TextEditor(text: $draftDescription)
                    .font(.system(size: 11))
                    .frame(height: 100)
                    .padding(6)
                    .scrollIndicators(.automatic)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .focused($descriptionFocused)
            } else {
                Group {
                    if let desc = project.projectDescription, !desc.isEmpty {
                        Text(desc).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("点击添加描述...").font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                }
                .onTapGesture {
                    draftDescription = project.projectDescription ?? ""
                    isEditingDescription = true
                    DispatchQueue.main.async { descriptionFocused = true }
                }
            }
        }
    }

    private func commitDescriptionEdit() {
        isEditingDescription = false
        let trimmed = draftDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = projectDetail?.projectDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmed != current else { return }
        Task {
            await viewModel.updateProjectDescription(ideaId: idea.id, description: trimmed.isEmpty ? nil : trimmed)
            await reloadDetail()
        }
    }

    private func planningBackgroundCard(_ project: ProjectDetailSnapshot) -> some View {
        DetailSectionCard(title: "规划背景", systemImage: "map", tint: .cyan, background: Color.cyan.opacity(0.08), border: Color.cyan.opacity(0.22), onBackgroundTap: dismissAllEditing) {
            VStack(alignment: .leading, spacing: 6) {
                if isEditingPlanningBackground {
                    TextEditor(text: $draftPlanningBackground)
                        .font(.system(size: 11))
                        .frame(height: 150)
                        .padding(6)
                        .scrollIndicators(.automatic)
                        .background(Color(nsColor: .windowBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .focused($planningBackgroundFocused)
                } else {
                    Group {
                        if let bg = project.planningBackground, !bg.isEmpty {
                            Text(bg).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(5).fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("点击添加规划背景...").font(.system(size: 11)).foregroundStyle(.tertiary)
                        }
                    }
                    .onTapGesture {
                        draftPlanningBackground = project.planningBackground ?? ""
                        isEditingPlanningBackground = true
                        DispatchQueue.main.async { planningBackgroundFocused = true }
                    }
                }

                // 研究提示词区域
                if let prompt = project.planningResearchPrompt, !prompt.isEmpty {
                    Divider().padding(.vertical, 2)
                    HStack(spacing: 4) {
                        Text("研究提示词").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(prompt, forType: .string)
                            showCopyPromptToast = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showCopyPromptToast = false }
                        } label: {
                            if showCopyPromptToast {
                                Label("已复制", systemImage: "checkmark").font(.system(size: 10)).foregroundStyle(.green)
                            } else {
                                Image(systemName: "doc.on.clipboard").font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .animation(.easeInOut(duration: 0.2), value: showCopyPromptToast)
                    }
                    Text(prompt).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)

                    HStack {
                        Spacer()
                        Button {
                            guard !isGeneratingPlanningPrompt else { return }
                            isGeneratingPlanningPrompt = true
                            Task {
                                await viewModel.generatePlanningBackgroundPrompt(ideaId: idea.id)
                                await reloadDetail()
                                isGeneratingPlanningPrompt = false
                            }
                        } label: {
                            if isGeneratingPlanningPrompt {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("重新生成").font(.system(size: 10))
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .disabled(isGeneratingPlanningPrompt)
                    }
                } else {
                    HStack {
                        Spacer()
                        Button {
                            guard !isGeneratingPlanningPrompt else { return }
                            isGeneratingPlanningPrompt = true
                            Task {
                                await viewModel.generatePlanningBackgroundPrompt(ideaId: idea.id)
                                await reloadDetail()
                                isGeneratingPlanningPrompt = false
                            }
                        } label: {
                            if isGeneratingPlanningPrompt {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("生成研究提示词", systemImage: "sparkles").font(.system(size: 10))
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .disabled(isGeneratingPlanningPrompt)
                    }
                }
            }
        }
    }

    private func commitPlanningBackgroundEdit() {
        isEditingPlanningBackground = false
        let trimmed = draftPlanningBackground.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = projectDetail?.planningBackground?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmed != current else { return }
        Task {
            await viewModel.updatePlanningBackground(ideaId: idea.id, planningBackground: trimmed.isEmpty ? nil : trimmed)
            await reloadDetail()
        }
    }

    private var tasksCard: some View {
        let sorted = allTasks.sorted { taskOrder($0) < taskOrder($1) }
        return DetailSectionCard(title: "关联必做项", systemImage: "list.bullet", tint: .green, background: Color.green.opacity(0.08), border: Color.green.opacity(0.22)) {
            VStack(alignment: .leading, spacing: 6) {
                if sorted.isEmpty {
                    Text("暂无关联必做项").font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                ForEach(sorted, id: \.id) { task in
                    HStack(spacing: 6) {
                        Text(taskStatusLabel(task))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(taskStatusTint(task))
                            .clipShape(Capsule())
                        Text(task.title).font(.system(size: 11)).lineLimit(1)
                        Spacer()
                        Text(task.isSettled ? "\(task.actualMinutes ?? 0)分钟" : "\(task.estimatedMinutes)分钟")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func taskOrder(_ task: DailyTaskEntity) -> Int {
        if !task.isSettled && (task.taskStatus == .running || task.taskStatus == .paused) { return 0 }
        if task.taskStatus == .done { return 1 }
        return 2
    }

    private func taskStatusLabel(_ task: DailyTaskEntity) -> String {
        if !task.isSettled {
            return task.taskStatus.displayName
        }
        return task.taskStatus == .done ? "已完成" : "未完成"
    }

    private func taskStatusTint(_ task: DailyTaskEntity) -> Color {
        if !task.isSettled && (task.taskStatus == .running || task.taskStatus == .paused) { return .blue }
        if task.taskStatus == .done { return .green }
        return .orange
    }

    // MARK: - Arrangement

    private var arrangementConfirmPage: some View {
        let isDelete = viewModel.pendingArrangementAction == .delete
        return ConfirmActionPage(
            icon: isDelete ? "trash" : "arrow.uturn.backward",
            iconTint: isDelete ? .red : .blue,
            title: viewModel.pendingArrangementTitle ?? "",
            message: isDelete ? "确认删除该安排？" : "确认重新激活该安排？",
            confirmLabel: isDelete ? "确认删除" : "确认激活",
            onCancel: { viewModel.cancelArrangementAction() },
            onConfirm: { Task { await viewModel.executeArrangementAction(projectId: idea.id) } }
        )
    }

    private var arrangementCard: some View {
        DetailSectionCard(title: "我的安排", systemImage: "calendar.badge.clock", tint: .blue, background: Color.blue.opacity(0.08), border: Color.blue.opacity(0.22), onBackgroundTap: dismissAllEditing) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(viewModel.arrangements, id: \.id) { item in
                    ArrangementRow(
                        item: item,
                        isPromoting: viewModel.promotingArrangementIds.contains(item.id),
                        onPromote: { priority in
                            Task {
                                await viewModel.promoteArrangementToMustDo(arrangementId: item.id, priority: priority)
                                await refreshAllTasks()
                            }
                        },
                        onUpdate: { content, minutes, deadline in
                            Task { await viewModel.updateArrangement(arrangementId: item.id, content: content, estimatedMinutes: minutes, deadline: deadline) }
                        },
                        onDelete: { viewModel.requestDeleteArrangement(id: item.id) },
                        onRevive: { viewModel.requestReviveArrangement(id: item.id) }
                    )
                }

                if viewModel.arrangements.isEmpty {
                    Text("暂无安排").font(.system(size: 11)).foregroundStyle(.tertiary)
                }

                HStack(spacing: 8) {
                    TextField("按 Enter 添加安排...", text: $newArrangementText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .lineLimit(1...3)
                        .focused($newArrangementFocused)
                        .onSubmit { addArrangement() }

                    Group {
                        if editingNewArrangementMinutes {
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                TextField("30m", text: $draftNewArrangementMinutes)
                                    .textFieldStyle(.plain)
                                    .frame(width: 52)
                                    .focused($newArrangementMinutesFocused)
                                    .onSubmit { commitNewArrangementMinutes() }
                            }
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                            .padding(.horizontal, 4).padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.1)).cornerRadius(3)
                        } else {
                            Label(newArrangementMinutes.hourMinuteString, systemImage: "clock")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .onTapGesture {
                                    draftNewArrangementMinutes = newArrangementMinutes.hourMinuteString
                                    editingNewArrangementMinutes = true
                                    DispatchQueue.main.async { newArrangementMinutesFocused = true }
                                }
                        }
                    }
                    .frame(width: 72)
                }
                .padding(8)
                .background(Color(nsColor: .windowBackgroundColor).contentShape(Rectangle()).onTapGesture { newArrangementMinutesFocused = false })
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func addArrangement() {
        let text = newArrangementText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // 默认截止时间：明天 23:59
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: .now)!
        let deadline = cal.date(bySettingHour: 23, minute: 59, second: 0, of: tomorrow)
        Task {
            await viewModel.addArrangement(projectId: idea.id, content: text, estimatedMinutes: newArrangementMinutes, deadline: deadline)
        }
        newArrangementText = ""
        newArrangementMinutes = 30
    }

    private func commitNewArrangementMinutes() {
        editingNewArrangementMinutes = false
        guard let minutes = draftNewArrangementMinutes.trimmingCharacters(in: .whitespacesAndNewlines).parsedHourMinuteDuration else { return }
        newArrangementMinutes = max(minutes, 5)
    }

    private var noteCard: some View {
        DetailSectionCard(title: "笔记", systemImage: "note.text", tint: .orange, background: Color.orange.opacity(0.08), border: Color.orange.opacity(0.22), onBackgroundTap: dismissAllEditing) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(notes, id: \.id) { note in
                    ProjectNoteRow(
                        note: note,
                        onUpdate: { content in
                            Task {
                                await viewModel.updateProjectNote(noteId: note.id, content: content)
                                notes = await viewModel.fetchProjectNotes(ideaId: idea.id)
                            }
                        }
                    )
                }

                HStack(spacing: 8) {
                    TextField("添加笔记...", text: $newNoteText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .focused($newNoteFocused)
                        .onSubmit { addNote() }
                    Button {
                        addNote()
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.system(size: 14)).foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func addNote() {
        let text = newNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        Task {
            await viewModel.addProjectNote(ideaId: idea.id, content: text)
            notes = await viewModel.fetchProjectNotes(ideaId: idea.id)
        }
        newNoteText = ""
    }
}

// MARK: - Shared Types

struct ProjectDetailSnapshot {
    let id: UUID
    let title: String
    let category: String
    let createdDate: Date
    let projectProgress: Double?
    let projectProgressSummary: String?
    let projectProgressUpdatedAt: Date?
    var projectDescription: String?
    var planningBackground: String?
    var planningResearchPrompt: String?
    var planningResearchPromptReason: String?

    init(idea: IdeaEntity) {
        id = idea.id
        title = idea.title
        category = idea.category
        createdDate = idea.createdDate
        projectProgress = idea.projectProgress
        projectProgressSummary = idea.projectProgressSummary
        projectProgressUpdatedAt = idea.projectProgressUpdatedAt
        projectDescription = idea.projectDescription
        planningBackground = idea.planningBackground
        planningResearchPrompt = idea.planningResearchPrompt
        planningResearchPromptReason = idea.planningResearchPromptReason
    }
}

// MARK: - Helper Views

struct DetailSectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    let background: Color
    let border: Color
    var onBackgroundTap: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            background
                .contentShape(Rectangle())
                .onTapGesture { onBackgroundTap?() }
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(border, lineWidth: 1))
    }
}

private struct ProjectNoteRow: View {
    let note: ProjectNoteEntity
    let onUpdate: (String) -> Void
    @State private var isEditing = false
    @State private var draftText = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if isEditing {
                TextEditor(text: $draftText)
                    .font(.system(size: 11))
                    .frame(minHeight: 60)
                    .padding(6)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .focused($isFocused)
            } else {
                Text(note.content).font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onTapGesture {
                        draftText = note.content
                        isEditing = true
                        DispatchQueue.main.async { isFocused = true }
                    }
            }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused && isEditing { commitEdit() }
        }
    }

    private func commitEdit() {
        isEditing = false
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != note.content.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        onUpdate(trimmed)
    }
}

// MARK: - Arrangement Row

private struct ArrangementRow: View {
    let item: ProjectArrangementEntity
    let isPromoting: Bool
    let onPromote: (TaskPriority) -> Void
    let onUpdate: (_ content: String?, _ estimatedMinutes: Int?, _ deadline: Date?) -> Void
    let onDelete: () -> Void
    let onRevive: () -> Void

    @State private var editingTitle = false
    @State private var editingMinutes = false
    @State private var editingDeadline = false
    @State private var draftTitle: String = ""
    @State private var draftMinutes: String = ""
    @State private var draftDeadline: String = ""
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case title, minutes, deadline }

    private var status: ArrangementStatus { item.arrangementStatus }
    private var isEditable: Bool { status == .pending }
    private var canPromote: Bool { status == .pending && !isPromoting }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 行 1：状态标记 + 标题
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: statusIcon)
                    .font(.system(size: 10))
                    .foregroundStyle(statusTint)
                    .padding(.top, 2)

                if editingTitle {
                    TextField("安排内容", text: $draftTitle, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .lineLimit(1...3)
                        .focused($focusedField, equals: .title)
                        .onSubmit { focusedField = nil }
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(3)
                } else {
                    Text(item.content)
                        .font(.system(size: 11))
                        .foregroundStyle(status == .done ? .tertiary : .secondary)
                        .strikethrough(status == .done)
                        .lineLimit(2)
                        .onTapGesture { if isEditable { startEditingTitle() } }
                }

                Spacer(minLength: 8)

                Menu {
                    ForEach(TaskPriority.allCases, id: \.self) { priority in
                        Button {
                            onPromote(priority)
                        } label: {
                            Label("优先级：\(priority.displayName)", systemImage: priority == .high ? "flag.fill" : "flag")
                        }
                    }
                } label: {
                    if isPromoting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.green)
                    }
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .help("加入必做项")
                .disabled(!canPromote)
                .opacity(canPromote ? 1 : 0.35)
            }

            // 行 2：时间 + 截止日期 + 操作按钮
            HStack(spacing: 8) {
                if editingMinutes {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                        TextField("1h30m", text: $draftMinutes)
                            .textFieldStyle(.plain)
                            .frame(width: 52)
                            .focused($focusedField, equals: .minutes)
                            .onSubmit { commitMinutesEdit() }
                    }
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.1)).cornerRadius(3)
                } else {
                    Label(item.estimatedMinutes.hourMinuteString, systemImage: "clock")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .onTapGesture { if isEditable { startEditingMinutes() } }
                }

                if editingDeadline {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                        TextField("M-d", text: $draftDeadline)
                            .textFieldStyle(.plain)
                            .frame(width: 72)
                            .focused($focusedField, equals: .deadline)
                            .onSubmit { commitDeadlineEdit() }
                    }
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.1)).cornerRadius(3)
                } else if let deadline = item.deadline {
                    Label(deadline.deadlineDisplayString, systemImage: "calendar")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .onTapGesture { if isEditable { startEditingDeadline() } }
                } else if isEditable {
                    Label("添加截止...", systemImage: "calendar")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .onTapGesture { startEditingDeadline() }
                }

                Spacer()

                if status == .done {
                    Button(action: onRevive) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("复活")
                }

                if status != .inProgress {
                    Button(action: onDelete) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("删除")
                }
            }
        }
        .padding(8)
        .background { Color(nsColor: .textBackgroundColor).contentShape(Rectangle()).onTapGesture { focusedField = nil } }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onChange(of: focusedField) { _, newValue in
            if newValue == nil {
                if editingTitle { commitTitleEdit() }
                if editingMinutes { commitMinutesEdit() }
                if editingDeadline { commitDeadlineEdit() }
            }
        }
    }

    private var statusIcon: String {
        switch status {
        case .pending: return "circle"
        case .inProgress: return "circle.fill"
        case .done: return "checkmark"
        }
    }

    private var statusTint: Color {
        switch status {
        case .pending: return .secondary
        case .inProgress: return .blue
        case .done: return .green
        }
    }

    private func startEditingTitle() {
        if editingMinutes { commitMinutesEdit() }; if editingDeadline { commitDeadlineEdit() }
        draftTitle = item.content; editingTitle = true; focusedField = .title
    }
    private func commitTitleEdit() {
        editingTitle = false
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != item.content else { return }
        onUpdate(trimmed, nil, nil)
    }

    private func startEditingMinutes() {
        if editingTitle { commitTitleEdit() }; if editingDeadline { commitDeadlineEdit() }
        draftMinutes = item.estimatedMinutes.hourMinuteString; editingMinutes = true; focusedField = .minutes
    }
    private func commitMinutesEdit() {
        editingMinutes = false
        guard let minutes = draftMinutes.trimmingCharacters(in: .whitespacesAndNewlines).parsedHourMinuteDuration else { return }
        guard minutes != item.estimatedMinutes else { return }
        onUpdate(nil, minutes, nil)
    }

    private func startEditingDeadline() {
        if editingTitle { commitTitleEdit() }; if editingMinutes { commitMinutesEdit() }
        draftDeadline = item.deadline?.deadlineDisplayString ?? ""; editingDeadline = true; focusedField = .deadline
    }
    private func commitDeadlineEdit() {
        editingDeadline = false
        let trimmed = draftDeadline.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty || isValidDeadlineFormat(trimmed) else { return }
        let (parsed, _, _) = DeepSeekAIService.parseDeadlineString(trimmed.isEmpty ? nil : trimmed)
        if parsed != item.deadline {
            onUpdate(nil, nil, parsed)
        }
    }

    private func isValidDeadlineFormat(_ string: String) -> Bool {
        let parts = string.split(separator: " ", omittingEmptySubsequences: true)
        guard let datePart = parts.first else { return false }
        let dateComps = datePart.split(separator: "-").compactMap { Int($0) }
        guard dateComps.count == 2 || dateComps.count == 3 else { return false }
        if dateComps.count == 2 {
            guard dateComps[0] >= 1 && dateComps[0] <= 12, dateComps[1] >= 1 && dateComps[1] <= 31 else { return false }
        } else {
            guard dateComps[0] >= 1, dateComps[1] >= 1 && dateComps[1] <= 12, dateComps[2] >= 1 && dateComps[2] <= 31 else { return false }
        }
        if parts.count > 1 {
            let timeComps = String(parts[1]).split(separator: ":").compactMap { Int($0) }
            guard timeComps.count >= 1 && timeComps.count <= 2 else { return false }
            guard timeComps[0] >= 0 && timeComps[0] <= 23 else { return false }
            if timeComps.count == 2 { guard timeComps[1] >= 0 && timeComps[1] <= 59 else { return false } }
        }
        return true
    }
}
