import Foundation
import SwiftUI
import SwiftData

/// 全局应用状态
@Observable
final class AppState {

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

    enum Page {
        case main
        case summary
        case history
        case settings
    }

    // MARK: - Init

    init(modelContainer: ModelContainer, timerEngine: TimerEngine) {
        self.modelContainer = modelContainer
        self.timerEngine = timerEngine
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

        inputViewModel = InputViewModel(taskManager: taskMgr)
        ideaPoolViewModel = IdeaPoolViewModel(taskManager: taskMgr)
        mustDoViewModel = MustDoViewModel(taskManager: taskMgr)

        // 连接回调：提交成功后刷新想法池并展开
        inputViewModel?.onSubmitSuccess = { [weak self] in
            guard let ideaPoolVM = self?.ideaPoolViewModel else { return }
            ideaPoolVM.isExpanded = true
            await ideaPoolVM.refresh()
        }
    }
}
