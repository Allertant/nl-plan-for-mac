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
                    onDismiss: { appState.currentPage = .ideaPool }
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
    @State private var activeTasks: [DailyTaskEntity] = []
    @State private var settledTasks: [DailyTaskEntity] = []
    @State private var notes: [ProjectNoteEntity] = []
    @State private var isLoading = true
    @State private var isGeneratingPlanningPrompt = false
    @State private var editingTitle = false
    @State private var draftTitle = ""
    @FocusState private var titleFocused: Bool

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
                        titleCard(project)
                        descriptionCard(project)
                        planningBackgroundCard(project)
                        progressCard(project)
                        tasksCard
                        noteCard
                    }
                    .padding(12)
                }
                .scrollIndicators(.never)
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
        activeTasks = await tasks
        settledTasks = await settled
        notes = await projectNotes

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

    @State private var showCopyToast = false

    private func summaryCard(_ project: ProjectDetailSnapshot) -> some View {
        DetailSectionCard(title: "项目信息", systemImage: "lightbulb.fill", tint: .yellow, background: Color.yellow.opacity(0.08), border: Color.yellow.opacity(0.22)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(project.title).font(.system(size: 15, weight: .semibold)).lineLimit(3)
                    Button {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(project.title, forType: .string)
                        showCopyToast = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showCopyToast = false }
                    } label: {
                        if showCopyToast {
                            Label("已复制", systemImage: "checkmark").font(.system(size: 11)).foregroundStyle(.green)
                        } else {
                            Image(systemName: "doc.on.clipboard").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("复制标题")
                    .animation(.easeInOut(duration: 0.2), value: showCopyToast)
                }
                HStack(spacing: 8) {
                    TagChip(text: project.category)
                    Text(project.createdDate.shortDateTimeString).font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                if project.attempted {
                    Text("已尝试").font(.system(size: 9, weight: .medium)).foregroundStyle(.orange)
                        .padding(.horizontal, 6).padding(.vertical, 2).background(Color.orange.opacity(0.12)).clipShape(Capsule())
                }
            }
        }
    }

    private func titleCard(_ project: ProjectDetailSnapshot) -> some View {
        DetailSectionCard(title: "标题", systemImage: "pencil", tint: .blue, background: Color.blue.opacity(0.08), border: Color.blue.opacity(0.22)) {
            VStack(alignment: .leading, spacing: 6) {
                if editingTitle {
                    TextField("项目标题", text: $draftTitle, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1...3)
                        .padding(6)
                        .background(Color(nsColor: .windowBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .focused($titleFocused)
                        .onSubmit { commitTitleEdit() }

                    HStack {
                        Spacer()
                        Button("保存") {
                            commitTitleEdit()
                        }
                        .font(.system(size: 10, weight: .medium))
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                    }
                } else {
                    HStack {
                        Text(project.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Spacer()
                        Button("编辑") {
                            draftTitle = project.title
                            editingTitle = true
                            DispatchQueue.main.async { titleFocused = true }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func commitTitleEdit() {
        let newTitle = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newTitle.isEmpty else { editingTitle = false; return }
        Task {
            await viewModel.updateIdea(ideaId: idea.id, title: newTitle)
            await reloadDetail()
        }
        editingTitle = false
        titleFocused = false
    }

    @State private var isEditingDescription = false
    @State private var draftProjectDescription = ""
    @FocusState private var isDescriptionFocused: Bool

    private func descriptionCard(_ project: ProjectDetailSnapshot) -> some View {
        DetailSectionCard(title: "项目描述", systemImage: "doc.text", tint: .purple, background: Color.purple.opacity(0.08), border: Color.purple.opacity(0.22)) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Spacer()
                    Button(isEditingDescription ? "取消" : "编辑") {
                        if isEditingDescription {
                            isEditingDescription = false
                            draftProjectDescription = project.projectDescription ?? ""
                            isDescriptionFocused = false
                        } else {
                            draftProjectDescription = project.projectDescription ?? ""
                            isEditingDescription = true
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }

                if isEditingDescription {
                    TextEditor(text: $draftProjectDescription)
                        .font(.system(size: 11))
                        .frame(minHeight: 84)
                        .padding(6)
                        .background(Color(nsColor: .windowBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .focused($isDescriptionFocused)

                    HStack {
                        Spacer()
                        Button("保存") {
                            Task {
                                await viewModel.updateProjectDescription(ideaId: idea.id, description: draftProjectDescription)
                                await reloadDetail()
                            }
                            isEditingDescription = false
                            isDescriptionFocused = false
                        }
                        .font(.system(size: 10, weight: .medium))
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                    }
                } else {
                    if let desc = project.projectDescription, !desc.isEmpty {
                        Text(desc).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("暂无描述").font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    @State private var isEditingPlanningBackground = false
    @State private var draftPlanningBackground = ""
    @State private var showCopyPromptToast = false
    @State private var showPlanningBackgroundSavedToast = false

    private func planningBackgroundCard(_ project: ProjectDetailSnapshot) -> some View {
        DetailSectionCard(title: "规划背景", systemImage: "map", tint: .cyan, background: Color.cyan.opacity(0.08), border: Color.cyan.opacity(0.22)) {
            VStack(alignment: .leading, spacing: 6) {
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
                        .frame(minHeight: 84)
                        .padding(6)
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
                        Text(bg).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("暂无规划背景").font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                }

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
                    Text(prompt).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(5...10)

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

    private func progressCard(_ project: ProjectDetailSnapshot) -> some View {
        DetailSectionCard(title: "进度", systemImage: "chart.bar", tint: .indigo, background: Color.indigo.opacity(0.08), border: Color.indigo.opacity(0.22)) {
            VStack(alignment: .leading, spacing: 6) {
                if let progress = project.projectProgress {
                    HStack(spacing: 6) {
                        ProgressView(value: progress / 100).progressViewStyle(.linear).tint(.indigo)
                        Text("\(Int(progress))%").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    }
                }
                if let summary = project.projectProgressSummary, !summary.isEmpty {
                    Text(summary).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if let updatedAt = project.projectProgressUpdatedAt {
                    Text("更新于 \(updatedAt.relativeTimeString)").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var tasksCard: some View {
        DetailSectionCard(title: "关联必做项", systemImage: "list.bullet", tint: .green, background: Color.green.opacity(0.08), border: Color.green.opacity(0.22)) {
            VStack(alignment: .leading, spacing: 6) {
                if activeTasks.isEmpty && settledTasks.isEmpty {
                    Text("暂无关联必做项").font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                ForEach(activeTasks, id: \.id) { task in
                    HStack(spacing: 6) {
                        Image(systemName: task.taskStatus == .done ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 10))
                            .foregroundStyle(task.taskStatus == .done ? .green : .orange)
                        Text(task.title).font(.system(size: 11)).lineLimit(1)
                        Spacer()
                        Text("\(task.estimatedMinutes)分钟").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                ForEach(settledTasks, id: \.id) { task in
                    HStack(spacing: 6) {
                        Image(systemName: task.taskStatus == .done ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 10))
                            .foregroundStyle(task.taskStatus == .done ? .green : .orange)
                        Text(task.title).font(.system(size: 11)).lineLimit(1)
                        Spacer()
                        Text("\(task.actualMinutes)分钟").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    .opacity(0.6)
                }
            }
        }
    }

    @State private var newNoteText = ""

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

                HStack(alignment: .top) {
                    TextField("添加笔记...", text: $newNoteText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .lineLimit(1...3)
                    Button {
                        let text = newNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { return }
                        Task {
                            await viewModel.addProjectNote(ideaId: idea.id, content: text)
                            notes = await viewModel.fetchProjectNotes(ideaId: idea.id)
                        }
                        newNoteText = ""
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
}

// MARK: - Shared Types

struct ProjectDetailSnapshot {
    let id: UUID
    let title: String
    let category: String
    let createdDate: Date
    let attempted: Bool
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
        attempted = idea.attempted
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
