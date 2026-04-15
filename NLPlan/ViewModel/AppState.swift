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
        return ZhipuAIService(apiKey: apiKey)
    }

    // MARK: - Private

    private func checkAPIKey() {
        isAPIKeyConfigured = KeychainStore.shared.load(key: AppConstants.apiKeyKeychainKey) != nil
    }

    func refreshAPIKeyStatus() {
        checkAPIKey()
    }
}
