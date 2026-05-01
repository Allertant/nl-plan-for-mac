import SwiftUI
import SwiftData

public struct NLPlanMenuBarScene: Scene {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @State private var appState: AppState

    let container: ModelContainer

    public init() {
        do {
            let schema = Schema([
                ThoughtEntity.self,
                IdeaEntity.self,
                DailyTaskEntity.self,
                ProjectNoteEntity.self,
                ProjectArrangementEntity.self,
                SessionLogEntity.self,
                DailySummaryEntity.self,
                ParseQueueItemEntity.self
            ])
            let config = ModelConfiguration(schema: schema)
            let mc = try ModelContainer(for: schema, configurations: [config])
            container = mc

            let engine = TimerEngine()
            if UserDefaults.standard.bool(forKey: AppConstants.allowParallelKey) {
                Task { await engine.setAllowParallel(true) }
            }
            _appState = State(initialValue: AppState(modelContainer: mc, timerEngine: engine))
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    public var body: some Scene {
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
