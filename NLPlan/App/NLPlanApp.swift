import SwiftUI
import SwiftData

@main
struct NLPlanApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @State private var appState: AppState

    let container: ModelContainer

    init() {
        do {
            let schema = Schema([
                ThoughtEntity.self,
                IdeaEntity.self,
                DailyTaskEntity.self,
                IdeaLogEntity.self,
                ProjectNoteEntity.self,
                TaskSettlementRecordEntity.self,
                SessionLogEntity.self,
                DailySummaryEntity.self,
                ParseQueueItemEntity.self
            ])
            let config = ModelConfiguration(schema: schema)
            let mc = try ModelContainer(for: schema, configurations: [config])
            container = mc

            let engine = TimerEngine()
            _appState = State(initialValue: AppState(modelContainer: mc, timerEngine: engine))
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MainContentView()
                .modelContainer(container)
                .environment(appState)
                .preferredColorScheme(appState.appearanceMode.colorScheme)
        } label: {
            MenuBarLabelView(appState: appState)
        }
        .menuBarExtraStyle(.window)
    }
}
