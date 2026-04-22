import Foundation
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

    // MARK: - Timer Display

    /// 当前是否有任务在计时
    var isTimerRunning: Bool = false

    /// 当前计时显示文本
    var timerDisplayText: String = ""

    /// 当前运行中的任务名称
    var currentTaskTitle: String = ""

    // MARK: - Processing State

    /// AI 是否正在处理中
    var isAIProcessing: Bool = false

    // MARK: - Navigation

    /// 当前显示的页面
    var currentPage: Page = .main

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

        static func == (lhs: Page, rhs: Page) -> Bool {
            switch (lhs, rhs) {
            case (.main, .main), (.ideaPool, .ideaPool), (.summary, .summary), (.history, .history), (.settings, .settings), (.cleanupDetail, .cleanupDetail):
                return true
            case (.queueDetail(let a), .queueDetail(let b)):
                return a == b
            default:
                return false
            }
        }

        var queueItemID: UUID? {
            if case .queueDetail(let id) = self { return id }
            return nil
        }
    }

    // MARK: - Init

    init(modelContainer: ModelContainer, timerEngine: TimerEngine) {
        self.modelContainer = modelContainer
        self.timerEngine = timerEngine
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
        let taskRepo = TaskRepository(modelContext: context)
        let thoughtRepo = ThoughtRepository(modelContext: context)
        let sessionLogRepo = SessionLogRepository(modelContext: context)
        let aiService = makeAIService()

        let taskMgr = TaskManager(
            taskRepo: taskRepo,
            thoughtRepo: thoughtRepo,
            sessionLogRepo: sessionLogRepo,
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
        inputViewModel?.onSubmitSuccess = { [weak self] taskIds in
            guard let ideaPoolVM = self?.ideaPoolViewModel else { return }
            await ideaPoolVM.refresh(newTaskIds: Set(taskIds))
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
            await self?.ideaPoolViewModel?.refreshProjectAnalyses(taskId: ideaId)
        }
    }
}
