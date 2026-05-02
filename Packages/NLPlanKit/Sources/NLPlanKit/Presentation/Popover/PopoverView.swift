import SwiftUI

/// 主面板容器
struct PopoverView: View {
    @Environment(AppState.self) private var appState

    @Bindable var inputViewModel: InputViewModel
    @Bindable var ideaPoolViewModel: IdeaPoolViewModel
    @Bindable var mustDoViewModel: MustDoViewModel

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
                            ideaPoolIdeas: ideaPoolViewModel.ideas,
                            projects: ideaPoolViewModel.projects
                        )
                    }
                    .frame(minHeight: 440, alignment: .top)
                    .padding(12)
                    .background(ScrollViewScrollerHider())
                    .background(
                        Color(nsColor: .textBackgroundColor)
                            .contentShape(Rectangle())
                            .onTapGesture { NSApp.keyWindow?.makeFirstResponder(nil) }
                    )
                }
                .scrollIndicators(.never)

                Divider()

                // 底部操作栏
                HStack(spacing: 12) {
                    Spacer()

                    ToolbarIconButton {
                        appState.currentPage = .ideaPool
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "lightbulb.fill")
                            if ideaPoolViewModel.pendingCount > 0 {
                                Text("\(ideaPoolViewModel.pendingCount)")
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
                        if let pendingDate = appState.pendingSettlementDate {
                            appState.openSummary(for: pendingDate)
                        } else {
                            appState.openSummary(for: .now)
                        }
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
                if !ideaPoolViewModel.ideas.isEmpty && !mustDoViewModel.showRecommendationPanel && appState.pendingSettlementDate == nil {
                    AIRecommendFloatingButton(
                        viewModel: mustDoViewModel,
                        ideaPoolIdeas: ideaPoolViewModel.ideas,
                        projects: ideaPoolViewModel.projects,
                        remainingWorkHours: remainingWorkHours
                    )
                    .padding(.trailing, 14)
                    .padding(.bottom, 48)
                }
            }
            .overlay {
                if let confirmAction = mustDoViewModel.pendingConfirm {
                    confirmOverlay(for: confirmAction)
                }
            }
            .onAppear {
                Task {
                    await ideaPoolViewModel.refresh()
                    await mustDoViewModel.refresh()
                }
            }
    }

    @ViewBuilder
    private func confirmOverlay(for action: MustDoViewModel.ConfirmAction) -> some View {
        switch action {
        case .complete:
            ConfirmActionPage(
                icon: "checkmark.circle",
                iconTint: .green,
                title: mustDoViewModel.confirmTaskTitle ?? "",
                message: "确认标记为已完成？",
                confirmLabel: "确认完成",
                onCancel: { mustDoViewModel.cancelConfirm() },
                onConfirm: { Task { await mustDoViewModel.executeConfirm() } }
            )
            .background(.ultraThinMaterial)
        case .demote:
            ConfirmActionPage(
                icon: "arrow.uturn.backward",
                iconTint: .orange,
                title: mustDoViewModel.confirmTaskTitle ?? "",
                message: "确认移回想法池？",
                confirmLabel: "确认移回",
                onCancel: { mustDoViewModel.cancelConfirm() },
                onConfirm: { Task { await mustDoViewModel.executeConfirm() } }
            )
            .background(.ultraThinMaterial)
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
    let ideaPoolIdeas: [IdeaEntity]
    let projects: [ProjectEntity]
    let remainingWorkHours: Double

    @State private var isExpanded = false
    @State private var extraContext: String = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            // 策略小球
            if isExpanded {
                VStack(spacing: 6) {
                    ForEach(MustDoViewModel.RecommendationStrategy.allCases, id: \.self) { strategy in
                        strategyBall(strategy)
                    }
                }
                .transition(.scale(scale: 0.5).combined(with: .opacity))
            }

            // 输入框 + 主按钮
            HStack(alignment: .center, spacing: 8) {
                if isExpanded {
                    TextField("额外要求（可选）", text: $extraContext, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...4)
                        .font(.system(size: 11))
                        .padding(8)
                        .frame(width: 200, alignment: .leading)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                        .focused($isInputFocused)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                    }
                    if isExpanded {
                        DispatchQueue.main.async { isInputFocused = true }
                    } else {
                        extraContext = ""
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
        .onChange(of: ideaPoolIdeas.map(\.id)) {
            updateCanSuggest()
        }
        .task { updateCanSuggest() }
    }

    private func updateCanSuggest() {
        viewModel.updateCanSuggest(projects: projects)
    }

    private func strategyBall(_ strategy: MustDoViewModel.RecommendationStrategy) -> some View {
        let isDisabled = strategy == .suggest && !viewModel.canSuggest
        return Button {
            let context = extraContext.trimmingCharacters(in: .whitespacesAndNewlines)
            viewModel.recommendationStrategy = strategy
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isExpanded = false
            }
            extraContext = ""
            isInputFocused = false
            viewModel.fetchRecommendations(
                ideaPoolIdeas: ideaPoolIdeas,
                projects: projects,
                remainingHours: remainingWorkHours,
                extraContext: context.isEmpty ? nil : context
            )
        } label: {
            Text(strategy.shortName)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(isDisabled ? Color(nsColor: .disabledControlTextColor) : .white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isDisabled ? Color(nsColor: .disabledControlTextColor).opacity(0.2) : Color.accentColor)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(isDisabled ? "当前没有需要 AI 提示的项目" : "")
        .shadow(color: .black.opacity(isDisabled ? 0 : 0.15), radius: 3, x: 0, y: 2)
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
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .padding(8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 8)
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
