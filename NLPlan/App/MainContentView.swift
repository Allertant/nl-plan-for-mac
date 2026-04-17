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

            case .settings:
                SettingsContainerView()

            case .queueDetail:
                QueueDetailContainerView()
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
    @State private var viewModel: SettingsViewModel?

    var body: some View {
        Group {
            if let viewModel {
                SettingsView(viewModel: viewModel, onClose: {
                    appState.currentPage = .main
                })
            } else {
                ProgressView("加载中...")
                    .frame(width: 360, height: 520)
            }
        }
        .task {
            if viewModel == nil {
                viewModel = SettingsViewModel(appState: appState)
            }
        }
    }
}
