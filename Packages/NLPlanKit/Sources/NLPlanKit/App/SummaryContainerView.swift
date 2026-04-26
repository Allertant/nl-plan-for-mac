import SwiftUI

/// Summary 容器视图
struct SummaryContainerView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if let summaryVM = appState.summaryViewModel {
                SummaryView(viewModel: summaryVM) {
                    // 结算完成后清除待结算日期
                    if summaryVM.summary != nil,
                       let pendingDate = appState.pendingSettlementDate,
                       Calendar.current.isDate(summaryVM.settlementDate, inSameDayAs: pendingDate) {
                        appState.pendingSettlementDate = nil
                    }
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
                let ideaRepo = IdeaRepository(modelContext: context)
                let dailyTaskRepo = DailyTaskRepository(modelContext: context)
                let sessionLogRepo = SessionLogRepository(modelContext: context)
                let summaryRepo = SummaryRepository(modelContext: context)
                let aiService = appState.makeAIService()

                let dayMgr = DayManager(
                    ideaRepo: ideaRepo,
                    dailyTaskRepo: dailyTaskRepo,
                    summaryRepo: summaryRepo,
                    sessionLogRepo: sessionLogRepo,
                    timerEngine: appState.timerEngine,
                    aiService: aiService
                )
                let taskMgr = TaskManager(
                    ideaRepo: ideaRepo,
                    dailyTaskRepo: dailyTaskRepo,
                    thoughtRepo: ThoughtRepository(modelContext: context),
                    sessionLogRepo: sessionLogRepo,
                    aiService: aiService,
                    timerEngine: appState.timerEngine
                )
                appState.summaryViewModel = SummaryViewModel(
                    dayManager: dayMgr,
                    taskManager: taskMgr,
                    settlementDate: appState.settlementDate
                )
            }
        }
    }
}
