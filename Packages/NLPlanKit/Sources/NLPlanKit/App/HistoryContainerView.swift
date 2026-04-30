import SwiftUI

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
            let ideaRepo = IdeaRepository(modelContext: context)
            let dailyTaskRepo = DailyTaskRepository(modelContext: context)
            let sessionLogRepo = SessionLogRepository(modelContext: context)
            let summaryRepo = SummaryRepository(modelContext: context)
            let arrangementRepo = ProjectArrangementRepository(modelContext: context)
            let aiService = appState.makeAIService()

            let dayMgr = DayManager(
                ideaRepo: ideaRepo,
                dailyTaskRepo: dailyTaskRepo,
                summaryRepo: summaryRepo,
                sessionLogRepo: sessionLogRepo,
                arrangementRepo: arrangementRepo,
                timerEngine: appState.timerEngine,
                aiService: aiService
            )
            self.historyVM = HistoryViewModel(dayManager: dayMgr)
        }
    }
}
