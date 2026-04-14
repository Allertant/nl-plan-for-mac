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
                TaskEntity.self,
                SessionLogEntity.self,
                DailySummaryEntity.self
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
        } label: {
            MenuBarLabelView()
        }
        .menuBarExtraStyle(.window)
        .environment(appState)
    }
}
