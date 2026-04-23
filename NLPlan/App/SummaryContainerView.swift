import SwiftUI

/// Summary 容器视图
struct SummaryContainerView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if let summaryVM = appState.summaryViewModel {
                SummaryView(viewModel: summaryVM) {
                    appState.currentPage = .main
                }
            } else {
                ProgressView("加载中...")
                    .frame(width: 360, height: 520)
            }
        }
        .task {
            if appState.summaryViewModel == nil {
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
                appState.summaryViewModel = SummaryViewModel(
                    dayManager: dayMgr,
                    settlementDate: appState.settlementDate
                )
            }
        }
    }
}
