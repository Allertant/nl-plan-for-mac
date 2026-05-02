import SwiftUI
import SwiftData

/// 主内容容器 — 管理页面切换
struct MainContentView: View {
    @Environment(AppState.self) private var appState

    @State private var didInitialize = false
    @State private var midnightTimer: Timer?

    var body: some View {
        Group {
            switch appState.currentPage {
            case .main:
                PopoverContainerView()

            case .ideaPool, .projectDetail:
                IdeaPoolContainerView()
                    .overlay {
                        if case .projectDetail = appState.currentPage {
                            ProjectDetailContainerView()
                        }
                    }

            case .summary:
                SummaryContainerView()

            case .history:
                HistoryContainerView()

            case .settings:
                SettingsContainerView()

            case .queueDetail:
                QueueDetailContainerView()

            case .cleanupDetail:
                CleanupDetailContainerView()

            case .historyDetail:
                HistoryDetailContainerView()
            }
        }
        .task {
            guard !didInitialize else { return }
            didInitialize = true
            await performStartupChecks()
            scheduleMidnightCheck()
        }
        .onDisappear {
            midnightTimer?.invalidate()
            midnightTimer = nil
        }
    }

    private func performStartupChecks() async {
        let dayMgr = makeDayManager()

        do {
            appState.pendingSettlementDate = try dayMgr.pendingSettlementDate()
        } catch {
            print("启动检查失败：\(error)")
        }
    }

    private func makeDayManager() -> DayManager {
        let context = appState.modelContainer.mainContext
        return DayManager(
            ideaRepo: IdeaRepository(modelContext: context),
            projectRepo: ProjectRepository(modelContext: context),
            dailyTaskRepo: DailyTaskRepository(modelContext: context),
            summaryRepo: SummaryRepository(modelContext: context),
            sessionLogRepo: SessionLogRepository(modelContext: context),
            arrangementRepo: ProjectArrangementRepository(modelContext: context),
            timerEngine: appState.timerEngine,
            aiService: appState.makeAIService()
        )
    }

    private func scheduleMidnightCheck() {
        let calendar = Calendar.current
        let now = Date()
        let tomorrow = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now)!)
        let interval = tomorrow.timeIntervalSince(now) + 1

        midnightTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            Task { @MainActor in
                let dayMgr = makeDayManager()
                do {
                    appState.pendingSettlementDate = try dayMgr.pendingSettlementDate()
                } catch {
                    print("午夜结算检查失败：\(error)")
                }
                scheduleMidnightCheck()
            }
        }
    }
}

// MARK: - Popover Container

/// Popover 容器视图，从 AppState 获取 ViewModel 实例
struct PopoverContainerView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if let inputVM = appState.inputViewModel,
               let ideaPoolVM = appState.ideaPoolViewModel,
               let mustDoVM = appState.mustDoViewModel {
                PopoverView(
                    inputViewModel: inputVM,
                    ideaPoolViewModel: ideaPoolVM,
                    mustDoViewModel: mustDoVM
                )
            } else {
                ProgressView("加载中...")
                    .frame(width: 360, height: 520)
            }
        }
        .task {
            appState.ensureViewModelsInitialized()
        }
    }
}

// MARK: - Settings Container

/// Settings 容器视图
struct SettingsContainerView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = SettingsViewModel()

    var body: some View {
        SettingsView(viewModel: viewModel, onClose: {
            appState.currentPage = .main
        })
        .task {
            viewModel.appState = appState
            await appState.timerEngine.setAllowParallel(viewModel.allowParallel)
        }
    }
}

// MARK: - Cleanup Detail Container

struct CleanupDetailContainerView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if let ideaPoolVM = appState.ideaPoolViewModel {
                CleanupDetailView(viewModel: ideaPoolVM) {
                    appState.currentPage = .ideaPool
                }
            } else {
                ProgressView("加载中...")
                    .frame(width: 360, height: 520)
            }
        }
    }
}

// MARK: - IdeaPool Container

struct IdeaPoolContainerView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if let ideaPoolVM = appState.ideaPoolViewModel {
                IdeaPoolPageView(viewModel: ideaPoolVM) {
                    appState.currentPage = .main
                }
            } else {
                ProgressView("加载中...")
                    .frame(width: 360, height: 520)
            }
        }
    }
}
