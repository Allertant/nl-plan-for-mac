import SwiftUI
import SwiftData

/// 主内容容器 — 管理页面切换
struct MainContentView: View {
    @Environment(AppState.self) private var appState

    @State private var didInitialize = false

    var body: some View {
        Group {
            switch appState.currentPage {
            case .main:
                PopoverContainerView()

            case .summary:
                SummaryContainerView()

            case .history:
                HistoryContainerView()
            }
        }
        .sheet(isPresented: Bindable(appState).showSettings) {
            SettingsView()
                .environment(appState)
        }
        .task {
            guard !didInitialize else { return }
            didInitialize = true
            await performStartupChecks()
        }
    }

    private func performStartupChecks() async {
        let context = appState.modelContainer.mainContext
        let taskRepo = TaskRepository(modelContext: context)
        let sessionLogRepo = SessionLogRepository(modelContext: context)
        let summaryRepo = SummaryRepository(modelContext: context)
        let engine = appState.timerEngine
        let aiService = appState.makeAIService()
        let dayMgr = DayManager(
            taskRepo: taskRepo,
            summaryRepo: summaryRepo,
            sessionLogRepo: sessionLogRepo,
            timerEngine: engine,
            aiService: aiService
        )

        do {
            _ = try await dayMgr.migrateUnfinishedMustDo()
            _ = try await dayMgr.checkAndGradeYesterday()
        } catch {
            print("启动检查失败：\(error)")
        }
    }
}

// MARK: - Popover Container

/// Popover 容器视图，持有 ViewModel 实例
struct PopoverContainerView: View {
    @Environment(AppState.self) private var appState

    @State private var inputVM: InputViewModel?
    @State private var ideaPoolVM: IdeaPoolViewModel?
    @State private var mustDoVM: MustDoViewModel?

    var body: some View {
        Group {
            if let inputVM, let ideaPoolVM, let mustDoVM {
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
            let context = appState.modelContainer.mainContext
            let taskRepo = TaskRepository(modelContext: context)
            let thoughtRepo = ThoughtRepository(modelContext: context)
            let sessionLogRepo = SessionLogRepository(modelContext: context)
            let aiService = appState.makeAIService()

            let taskMgr = TaskManager(
                taskRepo: taskRepo,
                thoughtRepo: thoughtRepo,
                sessionLogRepo: sessionLogRepo,
                aiService: aiService,
                timerEngine: appState.timerEngine
            )

            self.inputVM = InputViewModel(taskManager: taskMgr)
            self.ideaPoolVM = IdeaPoolViewModel(taskManager: taskMgr)
            self.mustDoVM = MustDoViewModel(taskManager: taskMgr)
        }
    }
}

// MARK: - Summary Container

/// Summary 容器视图
struct SummaryContainerView: View {
    @Environment(AppState.self) private var appState

    @State private var summaryVM: SummaryViewModel?

    var body: some View {
        Group {
            if let summaryVM {
                SummaryView(viewModel: summaryVM) {
                    appState.currentPage = .main
                }
            } else {
                ProgressView("加载中...")
                    .frame(width: 360, height: 520)
            }
        }
        .task {
            let context = appState.modelContainer.mainContext
            let taskRepo = TaskRepository(modelContext: context)
            let sessionLogRepo = SessionLogRepository(modelContext: context)
            let summaryRepo = SummaryRepository(modelContext: context)
            let aiService = appState.makeAIService()

            let dayMgr = DayManager(
                taskRepo: taskRepo,
                summaryRepo: summaryRepo,
                sessionLogRepo: sessionLogRepo,
                timerEngine: appState.timerEngine,
                aiService: aiService
            )
            self.summaryVM = SummaryViewModel(dayManager: dayMgr)
        }
    }
}

// MARK: - History Container

/// History 容器视图
struct HistoryContainerView: View {
    @Environment(AppState.self) private var appState

    @State private var historyVM: HistoryViewModel?

    var body: some View {
        Group {
            if let historyVM {
                HistoryView(dayManager: historyVM.dayManager)
            } else {
                ProgressView("加载中...")
                    .frame(width: 360, height: 520)
            }
        }
        .task {
            let context = appState.modelContainer.mainContext
            let taskRepo = TaskRepository(modelContext: context)
            let sessionLogRepo = SessionLogRepository(modelContext: context)
            let summaryRepo = SummaryRepository(modelContext: context)
            let aiService = appState.makeAIService()

            let dayMgr = DayManager(
                taskRepo: taskRepo,
                summaryRepo: summaryRepo,
                sessionLogRepo: sessionLogRepo,
                timerEngine: appState.timerEngine,
                aiService: aiService
            )
            self.historyVM = HistoryViewModel(dayManager: dayMgr)
        }
    }
}
