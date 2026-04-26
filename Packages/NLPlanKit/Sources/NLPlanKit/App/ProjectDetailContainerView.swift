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
    @State private var activeTasks: [DailyTaskEntity] = []
    @State private var settledTasks: [DailyTaskEntity] = []
    @State private var notes: [ProjectNoteEntity] = []
    @State private var isLoading = true
    @State private var isPlanningBackgroundExpanded = false

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

    // MARK: - Cards

    private func summaryCard(_ project: ProjectDetailSnapshot) -> some View {
        DetailSectionCard(title: "项目信息", systemImage: "lightbulb.fill", tint: .yellow, background: Color.yellow.opacity(0.08), border: Color.yellow.opacity(0.22)) {
            VStack(alignment: .leading, spacing: 8) {
                Text(project.title).font(.system(size: 15, weight: .semibold)).lineLimit(3)
                HStack(spacing: 8) {
                    TagChip(text: project.category)
                    Text(project.createdDate.shortDateTimeString).font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                if project.attempted {
                    Text("已尝试").font(.system(size: 9, weight: .medium)).foregroundStyle(.orange)
                        .padding(.horizontal, 6).padding(.vertical, 2).background(Color.orange.opacity(0.12)).clipShape(Capsule())
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
        let hasBackground = project.planningBackground != nil && !project.planningBackground!.isEmpty
        return DetailSectionCard(title: "规划背景", systemImage: "map", tint: .cyan, background: Color.cyan.opacity(0.08), border: Color.cyan.opacity(0.22)) {
            if hasBackground {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.planningBackground!)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(isPlanningBackgroundExpanded ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                    if !isPlanningBackgroundExpanded {
                        Button("展开") {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                isPlanningBackgroundExpanded = true
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10))
                        .foregroundStyle(.cyan)
                    } else {
                        Button("收起") {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                isPlanningBackgroundExpanded = false
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10))
                        .foregroundStyle(.cyan)
                    }
                }
            } else {
                Text("暂无规划背景").font(.system(size: 11)).foregroundStyle(.tertiary)
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

    private var noteCard: some View {
        DetailSectionCard(title: "笔记", systemImage: "note.text", tint: .orange, background: Color.orange.opacity(0.08), border: Color.orange.opacity(0.22)) {
            VStack(alignment: .leading, spacing: 6) {
                if notes.isEmpty {
                    Text("暂无笔记").font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                ForEach(notes, id: \.id) { note in
                    Text(note.content).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
