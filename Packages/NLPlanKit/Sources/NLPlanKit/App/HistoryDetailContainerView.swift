import SwiftUI
import SwiftData

struct HistoryDetailContainerView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if let date = appState.currentPage.historyDetailDate {
                HistoryDetailPageView(date: date, onDismiss: {
                    appState.currentPage = .history
                })
            } else {
                ProgressView("加载中...")
                    .frame(width: 360, height: 520)
            }
        }
    }
}

private struct HistoryDetailPageView: View {
    @Environment(AppState.self) private var appState
    let date: Date
    let onDismiss: () -> Void

    @State private var summary: DailySummaryEntity?
    @State private var tasks: [DailyTaskEntity] = []
    @State private var sourceIdeas: [UUID: IdeaEntity] = [:]
    @State private var sourceProjects: [UUID: ProjectEntity] = [:]
    @State private var isLoading = true
    @State private var showingIdeaPopover: IdeaEntity?

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    BackButton(action: onDismiss).help("返回历史记录")
                    Image(systemName: "clock.fill").font(.system(size: 12)).foregroundStyle(.blue)
                    Text("历史详情").font(.system(size: 13, weight: .semibold))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Divider()

                if isLoading {
                    ProgressView("加载中...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if let summary {
                                gradeCard(summary)
                                evaluationCard(summary)
                            }
                            tasksCard
                        }
                        .padding(12)
                    }
                    .scrollIndicators(.never)
                }
            }
            .frame(width: 360, height: 520)
            .background(Color(nsColor: .windowBackgroundColor))

            // 想法弹窗覆盖层
            if let idea = showingIdeaPopover {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .onTapGesture { showingIdeaPopover = nil }

                ideaPopupCard(idea)
                    .zIndex(1)
            }
        }
        .task { await loadData() }
    }

    private func loadData() async {
        let context = appState.modelContainer.mainContext
        let ideaRepo = IdeaRepository(modelContext: context)
        let projectRepo = ProjectRepository(modelContext: context)
        let dailyTaskRepo = DailyTaskRepository(modelContext: context)
        let sessionLogRepo = SessionLogRepository(modelContext: context)
        let summaryRepo = SummaryRepository(modelContext: context)
        let arrangementRepo = ProjectArrangementRepository(modelContext: context)
        let aiService = appState.makeAIService()

        let dayMgr = DayManager(
            ideaRepo: ideaRepo,
            projectRepo: projectRepo,
            dailyTaskRepo: dailyTaskRepo,
            summaryRepo: summaryRepo,
            sessionLogRepo: sessionLogRepo,
            arrangementRepo: arrangementRepo,
            timerEngine: appState.timerEngine,
            aiService: aiService
        )

        do {
            summary = try await dayMgr.fetchSummary(date: date)
            tasks = try dailyTaskRepo.fetchAllTasks(date: date)
                .sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
        } catch {
            print("加载历史详情失败：\(error)")
        }

        for task in tasks {
            if let ideaId = task.sourceIdeaId, sourceIdeas[ideaId] == nil {
                if let idea = try? ideaRepo.fetchById(ideaId) {
                    sourceIdeas[ideaId] = idea
                }
            }
            if let projectId = task.sourceProjectId, sourceProjects[projectId] == nil {
                if let project = try? projectRepo.fetchById(projectId) {
                    sourceProjects[projectId] = project
                }
            }
        }

        isLoading = false
    }

    // MARK: - Grade Card

    private func gradeCard(_ summary: DailySummaryEntity) -> some View {
        let grade = summary.gradeEnum
        return DetailSectionCard(
            title: "评分等级",
            systemImage: "star.fill",
            tint: grade.historyColor,
            background: grade.historyColor.opacity(0.08),
            border: grade.historyColor.opacity(0.22)
        ) {
            VStack(spacing: 8) {
                Text(grade.displayName)
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(grade.historyColor)

                HStack(spacing: 12) {
                    Label("\(summary.completedCount)/\(summary.totalCount) 完成", systemImage: "checkmark.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Label("\(summary.totalActualMinutes) 分钟", systemImage: "clock")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Evaluation Card

    private func evaluationCard(_ summary: DailySummaryEntity) -> some View {
        DetailSectionCard(
            title: "AI 评价",
            systemImage: "text.bubble.fill",
            tint: .blue,
            background: Color.blue.opacity(0.08),
            border: Color.blue.opacity(0.22)
        ) {
            VStack(alignment: .leading, spacing: 6) {
                Text(summary.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let suggestion = summary.suggestion, !suggestion.isEmpty {
                    Divider().padding(.vertical, 2)
                    Text("建议")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(suggestion)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let basis = summary.gradingBasis, !basis.isEmpty {
                    Divider().padding(.vertical, 2)
                    Text("评分依据")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(basis)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Tasks Card

    private var tasksCard: some View {
        DetailSectionCard(
            title: "必做项",
            systemImage: "list.bullet.clipboard.fill",
            tint: .green,
            background: Color.green.opacity(0.08),
            border: Color.green.opacity(0.22)
        ) {
            VStack(alignment: .leading, spacing: 8) {
                if tasks.isEmpty {
                    Text("当日无必做项").font(.system(size: 11)).foregroundStyle(.tertiary)
                }

                ForEach(tasks, id: \.id) { task in
                    taskRow(task)
                }
            }
        }
    }

    private func taskRow(_ task: DailyTaskEntity) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: task.taskStatus == .done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 10))
                    .foregroundStyle(task.taskStatus == .done ? .green : .orange)

                Text(task.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(2)

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: task.taskPriority.iconName)
                        .font(.system(size: 8))
                        .foregroundStyle(colorForPriority(task.taskPriority))
                    Text(task.taskPriority.displayName)
                        .font(.system(size: 9))
                        .foregroundStyle(colorForPriority(task.taskPriority))
                }
            }

            HStack(spacing: 8) {
                TagChip(text: task.category)

                Text("预估 \(task.estimatedMinutes)分钟")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                if let actual = task.actualMinutes {
                    Text("实际 \(actual)分钟")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                if let completedAt = task.completedAt {
                    Text("完成于 \(completedAt.timeString)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

            if let incompletionReason = task.incompletionReason, !incompletionReason.isEmpty {
                Text("未完成原因：\(incompletionReason)")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let ideaId = task.sourceIdeaId, let idea = sourceIdeas[ideaId] {
                HStack {
                    Spacer()
                    Button {
                        showingIdeaPopover = idea
                    } label: {
                        Label("查看想法", systemImage: "lightbulb.fill")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
            } else if task.sourceProjectId != nil {
                HStack {
                    Spacer()
                    ProjectNavLink(ideaId: task.sourceProjectId!, returnTo: .historyDetail(date))
                }
            }
        }
        .padding(8)
        .background(task.taskStatus == .done
            ? Color.green.opacity(0.06)
            : Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Idea Popup Card

    private func ideaPopupCard(_ idea: IdeaEntity) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("想法详情")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    showingIdeaPopover = nil
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Text(idea.title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(3)

            HStack(spacing: 8) {
                TagChip(text: idea.category)
                Text(idea.createdDate.shortDateTimeString)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            if let note = idea.note, !note.isEmpty {
                Divider()
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(16)
        .frame(width: 260, height: 220)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 14, x: 0, y: 5)
    }

    // MARK: - Helpers

    private func colorForPriority(_ priority: TaskPriority) -> Color {
        switch priority {
        case .high: return .red
        case .medium: return .orange
        case .low: return .blue
        }
    }
}
