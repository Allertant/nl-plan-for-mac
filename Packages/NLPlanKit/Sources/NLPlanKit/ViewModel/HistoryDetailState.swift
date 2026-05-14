import Foundation
import SwiftData

@MainActor @Observable
final class HistoryDetailState {
    let date: Date

    var summary: DailySummaryEntity?
    var tasks: [DailyTaskEntity] = []
    var sourceIdeas: [UUID: IdeaEntity] = [:]
    var sourceProjects: [UUID: ProjectEntity] = [:]
    var isLoading = true

    private var hasLoaded = false

    init(date: Date) {
        self.date = Calendar.current.startOfDay(for: date)
    }

    func loadIfNeeded(appState: AppState) async {
        guard !hasLoaded else { return }
        await reload(appState: appState)
    }

    func reload(appState: AppState) async {
        isLoading = true

        let context = appState.modelContainer.mainContext
        let ideaRepo = IdeaRepository(modelContext: context)
        let projectRepo = ProjectRepository(modelContext: context)
        let dailyTaskRepo = DailyTaskRepository(modelContext: context)
        let sessionLogRepo = SessionLogRepository(modelContext: context)
        let summaryRepo = SummaryRepository(modelContext: context)
        let arrangementRepo = ProjectArrangementRepository(modelContext: context)
        let aiService = appState.makeAIService()
        let thoughtRepo = ThoughtRepository(modelContext: context)

        let dayMgr = DayManager(
            ideaRepo: ideaRepo,
            projectRepo: projectRepo,
            dailyTaskRepo: dailyTaskRepo,
            summaryRepo: summaryRepo,
            sessionLogRepo: sessionLogRepo,
            arrangementRepo: arrangementRepo,
            timerEngine: appState.timerEngine,
            aiService: aiService
        )
        let taskMgr = TaskManager(
            ideaRepo: ideaRepo,
            projectRepo: projectRepo,
            dailyTaskRepo: dailyTaskRepo,
            thoughtRepo: thoughtRepo,
            sessionLogRepo: sessionLogRepo,
            arrangementRepo: arrangementRepo,
            aiService: aiService,
            timerEngine: appState.timerEngine
        )

        var loadedSummary: DailySummaryEntity?
        var loadedTasks: [DailyTaskEntity] = []
        var loadedSourceIdeas: [UUID: IdeaEntity] = [:]
        var loadedSourceProjects: [UUID: ProjectEntity] = [:]

        do {
            loadedSummary = try await dayMgr.fetchSummary(date: date)
            loadedTasks = try dailyTaskRepo.fetchAllTasks(date: date)
                .sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
        } catch {
            print("加载历史详情失败：\(error)")
        }

        for task in loadedTasks {
            let sourceLookup = await taskMgr.fetchTaskSourceLookup(task: task)
            if let idea = sourceLookup.idea {
                loadedSourceIdeas[idea.id] = idea
            }
            if let project = sourceLookup.project {
                loadedSourceProjects[project.id] = project
            }
        }

        summary = loadedSummary
        tasks = loadedTasks
        sourceIdeas = loadedSourceIdeas
        sourceProjects = loadedSourceProjects
        isLoading = false
        hasLoaded = true
    }
}
