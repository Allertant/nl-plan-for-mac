import SwiftUI

/// 必做项列表区域
struct MustDoSection: View {
    @Bindable var viewModel: MustDoViewModel
    let ideaPoolTasks: [TaskEntity]
    let remainingWorkHours: Double
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
                    ForEach(viewModel.pendingTasks, id: \.id) { task in
                        MustDoTaskRow(
                            task: task,
                            timerEngine: timerEngine,
                            onStart: { Task { await viewModel.startTask(taskId: task.id) } },
                            onComplete: { Task { await viewModel.markComplete(taskId: task.id) } },
                            onDemote: { Task { await viewModel.demoteToIdeaPool(taskId: task.id) } }
                        )
                    }
                }
                .padding(.horizontal, 8)

                // 已完成任务
                if !viewModel.completedTasks.isEmpty {
                    Divider()
                        .padding(.horizontal, 12)

                    LazyVStack(spacing: 4) {
                        ForEach(viewModel.completedTasks, id: \.id) { task in
                            CompletedTaskRow(task: task)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }

            // AI 推荐按钮（面板展开时隐藏，避免两个 spinner 同时出现）
            if !ideaPoolTasks.isEmpty && !viewModel.showRecommendationPanel {
                AIRecommendButton(
                    viewModel: viewModel,
                    ideaPoolTasks: ideaPoolTasks,
                    remainingWorkHours: remainingWorkHours
                )
            }

            // AI 推荐面板
            if viewModel.showRecommendationPanel {
                AIRecommendPanel(viewModel: viewModel, ideaPoolTasks: ideaPoolTasks)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
            }
        }
    }
}

// MARK: - AI 推荐按钮

private struct AIRecommendButton: View {
    @Bindable var viewModel: MustDoViewModel
    let ideaPoolTasks: [TaskEntity]
    let remainingWorkHours: Double

    var body: some View {
        HStack(spacing: 6) {
            Picker("策略", selection: $viewModel.recommendationStrategy) {
                ForEach(MustDoViewModel.RecommendationStrategy.allCases) { strategy in
                    Text(strategy.displayName)
                        .font(.system(size: 10))
                        .tag(strategy)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)

            Spacer()

            Button {
                Task {
                    await viewModel.fetchRecommendations(
                        ideaPoolTasks: ideaPoolTasks,
                        remainingHours: remainingWorkHours
                    )
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11))
                    Text("AI 推荐")
                        .font(.system(size: 11))
                }
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }
}

// MARK: - AI 推荐面板

private struct AIRecommendPanel: View {
    @Bindable var viewModel: MustDoViewModel
    let ideaPoolTasks: [TaskEntity]

    private var ideaPoolLookup: [UUID: TaskEntity] {
        Dictionary(uniqueKeysWithValues: ideaPoolTasks.map { ($0.id, $0) })
    }

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
                Button {
                    viewModel.dismissRecommendations()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            switch viewModel.recommendationState {
            case .loading:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("AI 正在分析...")
                        .font(.system(size: 11))
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
                        if let task = ideaPoolLookup[rec.taskId] {
                            RecommendationRow(
                                task: task,
                                reason: rec.reason,
                                isAccepted: viewModel.acceptedRecommendationIds.contains(rec.taskId),
                                selectedPriority: Binding(
                                    get: { viewModel.selectedPriorities[rec.taskId] ?? .medium },
                                    set: { viewModel.selectedPriorities[rec.taskId] = $0 }
                                ),
                                onAccept: {
                                    Task { await viewModel.acceptRecommendation(taskId: rec.taskId) }
                                }
                            )
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
    let task: TaskEntity
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
                        .foregroundStyle(.tertiary)

                    Label("\(task.estimatedMinutes)分钟", systemImage: "clock")
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
    let task: TaskEntity
    let timerEngine: TimerEngine
    let onStart: () -> Void
    let onComplete: () -> Void
    let onDemote: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // 状态图标
            Image(systemName: task.taskStatus.iconName)
                .font(.system(size: 16))
                .foregroundStyle(task.status == TaskStatus.running.rawValue ? Color.green : Color.secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Label("预计\(task.estimatedMinutes)分钟", systemImage: "clock")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    if task.status == TaskStatus.running.rawValue {
                        RunningTimerView(taskId: task.id, timerEngine: timerEngine)
                    }
                }
            }

            Spacer()

            HStack(spacing: 4) {
                if task.status != TaskStatus.running.rawValue {
                    Button {
                        onStart()
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                    .help("开始执行")
                }

                Button {
                    onComplete()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .help("标记完成")

                Button {
                    onDemote()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("移回想法池")
            }
        }
        .padding(8)
        .background(
            task.status == TaskStatus.running.rawValue
            ? Color.green.opacity(0.08)
            : Color(nsColor: .textBackgroundColor)
        )
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(task.status == TaskStatus.running.rawValue ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }
}

/// 已完成任务卡片
struct CompletedTaskRow: View {
    let task: TaskEntity

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

            let minutes = task.totalElapsedSeconds / 60
            Text("\(minutes)分钟")
                .font(.system(size: 10))
                .foregroundStyle(.gray)
        }
        .padding(8)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
        .cornerRadius(6)
    }
}
