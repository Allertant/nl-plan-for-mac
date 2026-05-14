import SwiftUI
import SwiftData

struct HistoryDetailContainerView: View {
    @Environment(AppState.self) private var appState

    private var activeDate: Date? {
        if let date = appState.currentPage.historyDetailDate {
            return date
        }
        if case .projectDetail = appState.currentPage {
            return appState.returnPage?.historyDetailDate
        }
        return nil
    }

    var body: some View {
        Group {
            if let date = activeDate,
               let detailState = resolvedState(for: date) {
                HistoryDetailPageView(detailState: detailState) {
                    appState.currentPage = .history
                }
            } else {
                ProgressView("加载中...")
                    .frame(width: 360, height: 520)
            }
        }
        .task(id: activeDate) {
            guard let date = activeDate else { return }
            await prepareState(for: date)
        }
    }

    private func resolvedState(for date: Date) -> HistoryDetailState? {
        guard let state = appState.historyDetailState else { return nil }
        return Calendar.current.isDate(state.date, inSameDayAs: date) ? state : nil
    }

    private func prepareState(for date: Date) async {
        if appState.historyDetailState == nil
            || !(appState.historyDetailState.map { Calendar.current.isDate($0.date, inSameDayAs: date) } ?? false) {
            appState.historyDetailState = HistoryDetailState(date: date)
        }
        await appState.historyDetailState?.loadIfNeeded(appState: appState)
    }
}

private struct HistoryDetailPageView: View {
    @Environment(AppState.self) private var appState
    @Bindable var detailState: HistoryDetailState
    let onDismiss: () -> Void

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

                if detailState.isLoading {
                    ProgressView("加载中...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if let summary = detailState.summary {
                                gradeCard(summary)
                                evaluationCard(summary)
                            }
                            tasksCard
                        }
                        .padding(12)
                    }
                    .scrollIndicators(.never)
                    .background(
                        ScrollViewOffsetTracker(
                            offsetY: Binding(
                                get: { appState.historyDetailScrollOffsetY },
                                set: { appState.historyDetailScrollOffsetY = $0 }
                            ),
                            shouldRestore: Binding(
                                get: { appState.historyDetailNeedsOffsetRestore },
                                set: { appState.historyDetailNeedsOffsetRestore = $0 }
                            )
                        )
                    )
                }
            }
            .frame(width: 360, height: 520)
            .background(Color(nsColor: .windowBackgroundColor))

            if let idea = showingIdeaPopover {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .onTapGesture { showingIdeaPopover = nil }

                ideaPopupCard(idea)
                    .zIndex(1)
            }
        }
    }

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
                ZStack(alignment: .bottomTrailing) {
                    Text(grade.displayName)
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundStyle(grade.historyColor)

                    if let userGrade = summary.userGradeEnum {
                        Text(userGrade.displayName)
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(userGrade.historyColor)
                            .offset(x: 18, y: 18)
                    }
                }

                HStack(spacing: 12) {
                    Label("\(summary.completedCount)/\(summary.totalCount) 完成", systemImage: "checkmark.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Label(summary.totalActualMinutes.hourMinuteString, systemImage: "clock")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

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

    private var tasksCard: some View {
        DetailSectionCard(
            title: "必做项",
            systemImage: "list.bullet.clipboard.fill",
            tint: .green,
            background: Color.green.opacity(0.08),
            border: Color.green.opacity(0.22)
        ) {
            VStack(alignment: .leading, spacing: 8) {
                if detailState.tasks.isEmpty {
                    Text("当日无必做项").font(.system(size: 11)).foregroundStyle(.tertiary)
                }

                ForEach(detailState.tasks, id: \.id) { task in
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

                Text("预估 \(task.estimatedMinutes.hourMinuteString)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                if let actual = task.actualMinutes {
                    Text("实际 \(actual.hourMinuteString)")
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

            if let ideaId = task.sourceIdeaId, let idea = detailState.sourceIdeas[ideaId] {
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
            } else if let projectId = task.sourceProjectId, detailState.sourceProjects[projectId] != nil {
                HStack {
                    Spacer()
                    HoverTextButton("查看项目", color: .indigo, isEmphasized: true) {
                        appState.historyDetailNeedsOffsetRestore = true
                        appState.returnPage = .historyDetail(detailState.date)
                        appState.currentPage = .projectDetail(projectId)
                    }
                }
            }
        }
        .padding(8)
        .background(task.taskStatus == .done
            ? Color.green.opacity(0.06)
            : Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

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

    private func colorForPriority(_ priority: TaskPriority) -> Color {
        switch priority {
        case .high: return .red
        case .medium: return .orange
        case .low: return .blue
        }
    }
}
