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

    // 编辑状态
    @State private var isEditingPlanningBackground = false
    @State private var draftPlanningBackground = ""
    @State private var isGeneratingPlanningPrompt = false
    @State private var showCopyPromptToast = false
    @State private var newNoteText = ""

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
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        summaryCard(project)
                        descriptionCard(project)
                        planningBackgroundCard(project)
                        tasksCard
                        noteCard
                    }
                    .padding(12)
                }
                .scrollIndicators(.automatic)
            }
        }
        .frame(width: 360, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .task { await loadProjectDetail() }
    }

    private func loadProjectDetail() async {
        let ideaId = idea.id
        async let tasks = viewModel.fetchLinkedMustDoTasks(sourceIdeaId: ideaId)
        async let settled = viewModel.fetchSettledTasks(sourceIdeaId: ideaId)
        async let projectNotes = viewModel.fetchProjectNotes(ideaId: ideaId)
        let active = await tasks
        let settledList = await settled
        notes = await projectNotes

        let settledIds = Set(settledList.map(\.id))
        allTasks = active.filter { !settledIds.contains($0.id) } + settledList

        if let freshIdea = await viewModel.fetchIdea(ideaId: ideaId) {
            projectDetail = ProjectDetailSnapshot(idea: freshIdea)
        }
        isLoading = false
    }

    private func reloadDetail() async {
        guard let freshIdea = await viewModel.fetchIdea(ideaId: idea.id) else { return }
        projectDetail = ProjectDetailSnapshot(idea: freshIdea)
    }

    // MARK: - Cards

    private func summaryCard(_ project: ProjectDetailSnapshot) -> some View {
        DetailSectionCard(title: "项目信息", systemImage: "lightbulb.fill", tint: .yellow, background: Color.yellow.opacity(0.08), border: Color.yellow.opacity(0.22)) {
            VStack(alignment: .leading, spacing: 8) {
                Text(project.title).font(.system(size: 15, weight: .semibold)).lineLimit(3)
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
        DetailSectionCard(title: "项目描述", systemImage: "doc.text", tint: .purple, background: Color.purple.opacity(0.08), border: Color.purple.opacity(0.22)) {
            if let desc = project.projectDescription, !desc.isEmpty {
                Text(desc).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("暂无描述").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        }
    }

    private func planningBackgroundCard(_ project: ProjectDetailSnapshot) -> some View {
        DetailSectionCard(title: "规划背景", systemImage: "map", tint: .cyan, background: Color.cyan.opacity(0.08), border: Color.cyan.opacity(0.22)) {
            VStack(alignment: .leading, spacing: 6) {
                // 编辑按钮
                HStack {
                    Spacer()
                    Button(isEditingPlanningBackground ? "取消" : "编辑") {
                        if isEditingPlanningBackground {
                            isEditingPlanningBackground = false
                            draftPlanningBackground = project.planningBackground ?? ""
                        } else {
                            draftPlanningBackground = project.planningBackground ?? ""
                            isEditingPlanningBackground = true
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }

                if isEditingPlanningBackground {
                    TextEditor(text: $draftPlanningBackground)
                        .font(.system(size: 11))
                        .frame(height: 150)
                        .padding(6)
                        .scrollIndicators(.automatic)
                        .background(Color(nsColor: .windowBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    HStack {
                        Spacer()
                        Button("保存") {
                            Task {
                                await viewModel.updatePlanningBackground(ideaId: idea.id, planningBackground: draftPlanningBackground)
                                await reloadDetail()
                            }
                            isEditingPlanningBackground = false
                        }
                        .font(.system(size: 10, weight: .medium))
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                    }
                } else {
                    if let bg = project.planningBackground, !bg.isEmpty {
                        Text(bg).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(5).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("暂无规划背景").font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                }

                // 研究提示词区域
                if let prompt = project.planningResearchPrompt, !prompt.isEmpty {
                    Divider().padding(.vertical, 2)
                    HStack(spacing: 4) {
                        Text("研究提示词").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                        if let reason = project.planningResearchPromptReason, !reason.isEmpty {
                            Text("(\(reason))").font(.system(size: 9)).foregroundStyle(.tertiary).lineLimit(1)
                        }
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
                    Text(prompt).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(3)

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

    private var noteCard: some View {
        DetailSectionCard(title: "笔记", systemImage: "note.text", tint: .orange, background: Color.orange.opacity(0.08), border: Color.orange.opacity(0.22)) {
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
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(border, lineWidth: 1))
    }
}

private struct ProjectNoteRow: View {
    let note: ProjectNoteEntity
    let onUpdate: (String) -> Void
    @State private var isEditing = false
    @State private var draftText = ""

    var body: some View {
        if isEditing {
            VStack(spacing: 4) {
                TextEditor(text: $draftText)
                    .font(.system(size: 11))
                    .frame(minHeight: 60)
                    .padding(6)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                HStack {
                    Spacer()
                    Button("取消") { isEditing = false; draftText = note.content }
                        .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary)
                    Button("保存") {
                        onUpdate(draftText)
                        isEditing = false
                    }
                    .buttonStyle(.plain).font(.system(size: 10, weight: .medium)).foregroundStyle(Color.accentColor)
                }
            }
        } else {
            HStack(alignment: .top, spacing: 6) {
                Text(note.content).font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    draftText = note.content
                    isEditing = true
                } label: {
                    Image(systemName: "pencil").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
