import SwiftUI

/// 主面板容器
struct PopoverView: View {
    @Environment(AppState.self) private var appState

    @Bindable var inputViewModel: InputViewModel
    @Bindable var ideaPoolViewModel: IdeaPoolViewModel
    @Bindable var mustDoViewModel: MustDoViewModel

    let timerEngine: TimerEngine

    private var remainingWorkHours: Double {
        let workEndHour = UserDefaults.standard.double(forKey: AppConstants.workEndTimeKey)
        let endHour = workEndHour > 0 ? workEndHour : AppConstants.defaultWorkEndHour
        let now = Date()
        let calendar = Calendar.current
        let currentTime = Double(calendar.component(.hour, from: now)) + Double(calendar.component(.minute, from: now)) / 60.0
        return max(0, endHour - currentTime)
    }

    var body: some View {
        VStack(spacing: 0) {
                if !appState.isAPIKeyConfigured {
                    APIKeyNotConfiguredBanner()
                }

                if let pendingDate = appState.pendingSettlementDate {
                    PendingSettlementBanner(date: pendingDate) {
                        appState.pendingSettlementDate = nil
                        appState.openSummary(for: pendingDate)
                    }
                }

                ScrollView {
                    VStack(spacing: 12) {
                        // 输入区
                        InputSection(viewModel: inputViewModel)

                        // 解析队列
                        ParseQueueSection(viewModel: inputViewModel) { queueItemID in
                            appState.currentPage = .queueDetail(queueItemID)
                        }

                        // 必做项
                        MustDoSection(
                            viewModel: mustDoViewModel,
                            ideaPoolTasks: ideaPoolViewModel.tasks,
                            timerEngine: timerEngine
                        )
                    }
                    .padding(12)
                    .background(ScrollViewScrollerHider())
                }
                .scrollIndicators(.hidden)

                Divider()

                // 底部操作栏
                HStack(spacing: 12) {
                    Spacer()

                    ToolbarIconButton {
                        appState.currentPage = .ideaPool
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "lightbulb.fill")
                            if !ideaPoolViewModel.tasks.isEmpty {
                                Text("\(ideaPoolViewModel.tasks.count)")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.accentColor)
                                    .clipShape(Capsule())
                            }
                        }
                    }

                    ToolbarIconButton {
                        appState.openSummary(for: .now)
                    } label: {
                        if let vm = appState.summaryViewModel, vm.isProcessing {
                            ProgressView()
                                .controlSize(.small)
                        } else if let summary = appState.summaryViewModel?.summary {
                            Image(systemName: "flag.checkered")
                                .foregroundStyle(gradeColor(summary.gradeEnum))
                        } else {
                            Image(systemName: "flag.checkered")
                                .foregroundStyle(.secondary)
                        }
                    }

                    ToolbarIconButton {
                        appState.currentPage = .history
                    } label: {
                        Image(systemName: "calendar")
                    }

                    ToolbarIconButton {
                        appState.currentPage = .settings
                    } label: {
                        Image(systemName: "gear")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .frame(width: 360, height: 520)
            .overlay(alignment: .bottomTrailing) {
                // AI 推荐浮动按钮
                if !ideaPoolViewModel.tasks.isEmpty && !mustDoViewModel.showRecommendationPanel {
                    AIRecommendFloatingButton(
                        viewModel: mustDoViewModel,
                        ideaPoolTasks: ideaPoolViewModel.tasks,
                        remainingWorkHours: remainingWorkHours
                    )
                    .padding(.trailing, 14)
                    .padding(.bottom, 48)
                }
            }
            .onAppear {
                Task {
                    await ideaPoolViewModel.refresh()
                    await mustDoViewModel.refresh()
                }
            }
    }
}

private struct PendingSettlementBanner: View {
    let date: Date
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("有未结算的必做项")
                        .font(.system(size: 12, weight: .semibold))
                    Text("结算日期：\(date.dateString)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("去结算")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.1))
        }
        .buttonStyle(.plain)
    }
}

/// API Key 未配置横幅
struct APIKeyNotConfiguredBanner: View {
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("请先在设置中配置 API Key")
                .font(.system(size: 12))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
    }
}

// MARK: - AI 推荐浮动按钮

private struct AIRecommendFloatingButton: View {
    @Bindable var viewModel: MustDoViewModel
    let ideaPoolTasks: [TaskEntity]
    let remainingWorkHours: Double

    @State private var isExpanded = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // 策略小球（从底部向上弹出）
            if isExpanded {
                ForEach(Array(MustDoViewModel.RecommendationStrategy.allCases.enumerated()), id: \.element) { index, strategy in
                    strategyBall(strategy, offsetIndex: MustDoViewModel.RecommendationStrategy.allCases.count - 1 - index)
                }
            }

            // 主按钮
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: isExpanded ? "xmark" : "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(isExpanded ? Color.secondary : Color.accentColor)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.18), radius: 5, x: 0, y: 2)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .buttonStyle(.plain)
        }
    }

    private func strategyBall(_ strategy: MustDoViewModel.RecommendationStrategy, offsetIndex: Int) -> some View {
        Button {
            viewModel.recommendationStrategy = strategy
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isExpanded = false
            }
            Task {
                await viewModel.fetchRecommendations(
                    ideaPoolTasks: ideaPoolTasks,
                    remainingHours: remainingWorkHours
                )
            }
        } label: {
            Text(strategy.shortName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.accentColor)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 2)
        .offset(y: CGFloat(offsetIndex + 1) * -40)
        .transition(.scale(scale: 0.5).combined(with: .opacity))
    }
}

// MARK: - 底部工具栏图标按钮

private struct ToolbarIconButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            label()
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.primary.opacity(0.08) : .clear)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

private func gradeColor(_ grade: Grade) -> Color {
    switch grade {
    case .S: return .purple
    case .A: return .blue
    case .B: return .cyan
    case .C: return .green
    case .D: return .yellow
    case .E: return .orange
    case .F: return .red
    }
}
