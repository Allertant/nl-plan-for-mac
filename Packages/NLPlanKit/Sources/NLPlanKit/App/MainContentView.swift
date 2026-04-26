import SwiftUI
import SwiftData

/// 主内容容器 — 管理页面切换
struct MainContentView: View {
    @Environment(AppState.self) private var appState

    @State private var didInitialize = false
    @State private var secondaryPageOpacity: Double = 1

    var body: some View {
        Group {
            switch appState.currentPage {
            case .main:
                PopoverContainerView()

            case .ideaPool:
                IdeaPoolContainerView()

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

            case .projectDetail:
                ProjectDetailContainerView()
            }
        }
        .opacity(appState.currentPage == .main ? 1 : secondaryPageOpacity)
        .onChange(of: appState.currentPage) { _, newPage in
            if newPage != .main {
                secondaryPageOpacity = 0
                withAnimation(.easeIn(duration: 0.15)) {
                    secondaryPageOpacity = 1
                }
            }
        }
        .task {
            guard !didInitialize else { return }
            didInitialize = true
            await performStartupChecks()
        }
    }

    private func performStartupChecks() async {
        let context = appState.modelContainer.mainContext
        let ideaRepo = IdeaRepository(modelContext: context)
        let dailyTaskRepo = DailyTaskRepository(modelContext: context)
        let sessionLogRepo = SessionLogRepository(modelContext: context)
        let summaryRepo = SummaryRepository(modelContext: context)
        let engine = appState.timerEngine
        let aiService = appState.makeAIService()
        let dayMgr = DayManager(
            ideaRepo: ideaRepo,
            dailyTaskRepo: dailyTaskRepo,
            summaryRepo: summaryRepo,
            sessionLogRepo: sessionLogRepo,
            timerEngine: engine,
            aiService: aiService
        )

        do {
            appState.pendingSettlementDate = try dayMgr.pendingSettlementDate()
        } catch {
            print("启动检查失败：\(error)")
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
                    mustDoViewModel: mustDoVM,
                    timerEngine: appState.timerEngine
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
                    appState.currentPage = .main
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
