import SwiftUI

/// 主面板容器
struct PopoverView: View {
    @Environment(AppState.self) private var appState

    @Bindable var inputViewModel: InputViewModel
    @Bindable var ideaPoolViewModel: IdeaPoolViewModel
    @Bindable var mustDoViewModel: MustDoViewModel

    let timerEngine: TimerEngine

    @State private var hasScrollOverflow: Bool = false

    private var showBackToTopButton: Bool {
        ideaPoolViewModel.isExpanded &&
        (hasScrollOverflow || ideaPoolViewModel.tasks.count >= 5)
    }

    private var remainingWorkHours: Double {
        let workEndHour = UserDefaults.standard.double(forKey: AppConstants.workEndTimeKey)
        let endHour = workEndHour > 0 ? workEndHour : AppConstants.defaultWorkEndHour
        let now = Date()
        let calendar = Calendar.current
        let currentTime = Double(calendar.component(.hour, from: now)) + Double(calendar.component(.minute, from: now)) / 60.0
        return max(0, endHour - currentTime)
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                if !appState.isAPIKeyConfigured {
                    APIKeyNotConfiguredBanner()
                }

                ScrollView {
                    VStack(spacing: 12) {
                        Color.clear
                            .frame(height: 0)
                            .id("scroll-top-anchor")

                        // 输入区
                        InputSection(viewModel: inputViewModel)

                        // 解析队列
                        ParseQueueSection(viewModel: inputViewModel) { queueItemID in
                            appState.currentPage = .queueDetail(queueItemID)
                        }

                        // 想法池
                        IdeaPoolSection(viewModel: ideaPoolViewModel)

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
                .background(
                    ScrollViewStateObserver(hasOverflow: $hasScrollOverflow)
                )

                Divider()

                // 底部操作栏
                HStack(spacing: 16) {
                    Spacer()

                    Button {
                        appState.currentPage = .summary
                    } label: {
                        Label("今日总结", systemImage: "chart.bar")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)

                    Button {
                        appState.currentPage = .history
                    } label: {
                        Label("历史", systemImage: "calendar")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)

                    Button {
                        appState.currentPage = .settings
                    } label: {
                        Label("设置", systemImage: "gear")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .frame(width: 360, height: 520)
            .overlay(alignment: .bottomTrailing) {
                // 回到顶部按钮
                if showBackToTopButton {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo("scroll-top-anchor", anchor: .top)
                        }
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.borderless)
                    .contentShape(Circle())
                    .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))
                    .clipShape(Circle())
                    .overlay(
                        Circle().stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.18), radius: 5, x: 0, y: 2)
                    .padding(.trailing, 14)
                    .padding(.bottom, 78)
                    .zIndex(10)
                }

                // AI 推荐浮动按钮
                if !ideaPoolViewModel.tasks.isEmpty && !mustDoViewModel.showRecommendationPanel {
                    AIRecommendFloatingButton(
                        viewModel: mustDoViewModel,
                        ideaPoolTasks: ideaPoolViewModel.tasks,
                        remainingWorkHours: remainingWorkHours
                    )
                    .padding(.trailing, 14)
                    .padding(.bottom, 48)
                    .zIndex(9)
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
