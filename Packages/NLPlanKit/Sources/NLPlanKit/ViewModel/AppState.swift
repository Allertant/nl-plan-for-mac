import SwiftUI
import SwiftData
import AppKit

/// 全局应用状态
@Observable
final class AppState {

    enum AppearanceMode: String, CaseIterable, Identifiable {
        case system
        case light
        case dark

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .system: return "跟随系统"
            case .light: return "浅色"
            case .dark: return "深色"
            }
        }

        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }
    }

    // MARK: - Dependencies

    /// SwiftData 容器（由 App 层注入）
    let modelContainer: ModelContainer

    /// 计时引擎（全局共享）
    let timerEngine: TimerEngine

    // MARK: - Processing State

    /// AI 是否正在处理中
    var isAIProcessing: Bool = false

    // MARK: - Navigation

    /// 当前显示的页面
    var currentPage: Page = .main

    /// 当前总结页要结算的日期
    var settlementDate: Date = Calendar.current.startOfDay(for: .now)

    /// 需要用户补结算的日期。系统只提醒，不自动结算。
    var pendingSettlementDate: Date?

    /// 从二级页面返回时的目标页面（用于跨页面导航后正确返回）
    var returnPage: Page?

    /// 应用外观模式
    var appearanceMode: AppearanceMode = .system

    /// 是否显示设置页
    var showSettings: Bool = false

    /// 是否显示总结页
    var showSummary: Bool = false

    // MARK: - ViewModels (全局持有，避免面板关闭后重建丢失状态)

    var inputViewModel: InputViewModel?
    var ideaPoolViewModel: IdeaPoolViewModel?
    var mustDoViewModel: MustDoViewModel?
    var summaryViewModel: SummaryViewModel?

    // MARK: - API Key

    /// API Key 是否已配置
    var isAPIKeyConfigured: Bool = false

    // MARK: - Enums

    enum Page: Equatable {
        case main
        case ideaPool
        case summary
        case history
        case settings
        case queueDetail(UUID)
        case cleanupDetail
        case projectDetail(UUID)
        case historyDetail(Date)

        static func == (lhs: Page, rhs: Page) -> Bool {
            switch (lhs, rhs) {
            case (.main, .main), (.ideaPool, .ideaPool), (.summary, .summary), (.history, .history), (.settings, .settings), (.cleanupDetail, .cleanupDetail):
                return true
            case (.queueDetail(let a), .queueDetail(let b)):
                return a == b
            case (.projectDetail(let a), .projectDetail(let b)):
                return a == b
            case (.historyDetail(let a), .historyDetail(let b)):
                return Calendar.current.isDate(a, inSameDayAs: b)
            default:
                return false
            }
        }

        var queueItemID: UUID? {
            if case .queueDetail(let id) = self { return id }
            return nil
        }

        var projectItemID: UUID? {
            if case .projectDetail(let id) = self { return id }
            return nil
        }

        var historyDetailDate: Date? {
            if case .historyDetail(let date) = self { return date }
            return nil
        }
    }

    // MARK: - Init

    init(modelContainer: ModelContainer, timerEngine: TimerEngine) {
        self.modelContainer = modelContainer
        self.timerEngine = timerEngine
        LegacyPreferencesMigrator.migrateIfNeeded()
        loadAppearanceMode()
        checkAPIKey()
    }

    // MARK: - Factory

    /// 创建当前配置的 AI Service 实例
    func makeAIService() -> AIServiceProtocol {
        let apiKey = KeychainStore.shared.load(key: AppConstants.apiKeyKeychainKey) ?? ""
        let model = UserDefaults.standard.string(forKey: AppConstants.selectedModelKey) ?? AppConstants.defaultModel
        return DeepSeekAIService(apiKey: apiKey, model: model)
    }

    // MARK: - Private

    private func checkAPIKey() {
        isAPIKeyConfigured = KeychainStore.shared.load(key: AppConstants.apiKeyKeychainKey) != nil
    }

    func refreshAPIKeyStatus() {
        checkAPIKey()
    }

    func updateAppearanceMode(_ mode: AppearanceMode) {
        appearanceMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: AppConstants.appearanceModeKey)
        applyAppearanceMode(mode)
    }

    @MainActor
    func openSummary(for date: Date = .now) {
        settlementDate = Calendar.current.startOfDay(for: date)
        summaryViewModel = nil
        currentPage = .summary
    }

    private func loadAppearanceMode() {
        let raw = UserDefaults.standard.string(forKey: AppConstants.appearanceModeKey) ?? AppearanceMode.system.rawValue
        appearanceMode = AppearanceMode(rawValue: raw) ?? .system
        applyAppearanceMode(appearanceMode)
    }

    private func applyAppearanceMode(_ mode: AppearanceMode) {
        DispatchQueue.main.async {
            switch mode {
            case .system:
                NSApp.appearance = nil
            case .light:
                NSApp.appearance = NSAppearance(named: .aqua)
            case .dark:
                NSApp.appearance = NSAppearance(named: .darkAqua)
            }
        }
    }

    // MARK: - ViewModel Initialization

    /// 确保 ViewModel 已初始化（幂等）
    @MainActor
    func ensureViewModelsInitialized() {
        guard inputViewModel == nil else { return }

        let context = modelContainer.mainContext

        let ideaRepo = IdeaRepository(modelContext: context)
        let dailyTaskRepo = DailyTaskRepository(modelContext: context)
        let thoughtRepo = ThoughtRepository(modelContext: context)
        let sessionLogRepo = SessionLogRepository(modelContext: context)
        let arrangementRepo = ProjectArrangementRepository(modelContext: context)
        let aiService = makeAIService()

        let taskMgr = TaskManager(
            ideaRepo: ideaRepo,
            dailyTaskRepo: dailyTaskRepo,
            thoughtRepo: thoughtRepo,
            sessionLogRepo: sessionLogRepo,
            arrangementRepo: arrangementRepo,
            aiService: aiService,
            timerEngine: timerEngine
        )

        let parseQueueRepo = ParseQueueRepository(modelContext: context)

        inputViewModel = InputViewModel(taskManager: taskMgr, parseQueueRepo: parseQueueRepo)

        // 恢复未处理的队列项并继续处理
        inputViewModel?.loadQueue()
        Task {
            await inputViewModel?.resumeQueueProcessing()
        }
        ideaPoolViewModel = IdeaPoolViewModel(taskManager: taskMgr)
        mustDoViewModel = MustDoViewModel(taskManager: taskMgr)

        // 连接回调：提交成功后刷新想法池
        inputViewModel?.onSubmitSuccess = { [weak self] ideaIds in
            guard let ideaPoolVM = self?.ideaPoolViewModel else { return }
            await ideaPoolVM.refresh(newIdeaIds: Set(ideaIds))
        }

        // 连接回调：想法池提升到必做项后刷新必做项
        ideaPoolViewModel?.onPromotedToMustDo = { [weak self] in
            await self?.mustDoViewModel?.refresh()
        }

        // 连接回调：必做项移回想法池后刷新想法池
        mustDoViewModel?.onDemotedToIdeaPool = { [weak self] in
            await self?.ideaPoolViewModel?.refresh()
        }

        // 连接回调：推荐加入必做项后刷新想法池
        mustDoViewModel?.onIdeaPoolChanged = { [weak self] in
            await self?.ideaPoolViewModel?.refresh()
        }

        mustDoViewModel?.onProjectLinkChanged = { [weak self] ideaId in
            guard let ideaId else { return }
            await self?.ideaPoolViewModel?.refreshProjectAnalyses(ideaId: ideaId)
        }
    }
}
