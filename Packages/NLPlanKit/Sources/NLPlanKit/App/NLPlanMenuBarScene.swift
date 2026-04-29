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

    public var body: some Scene {
        MenuBarExtra {
            MainContentView()
                .modelContainer(container)
                .environment(appState)
                .preferredColorScheme(appState.appearanceMode.colorScheme)
                .onAppear { appDelegate.appState = appState }
        } label: {
            MenuBarLabelView(appState: appState)
        }
        .menuBarExtraStyle(.window)
    }
}
