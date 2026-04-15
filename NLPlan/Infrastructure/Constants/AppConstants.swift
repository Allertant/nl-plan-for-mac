import Foundation

/// 全局常量
enum AppConstants {
    /// 应用标识
    static let appIdentifier = "com.nlplan.mac"

    /// Keychain key for API Key
    static let apiKeyKeychainKey = "nlplan_deepseek_api_key"

    /// 输入长度上限
    static let maxInputLength = 2000

    /// 申诉次数上限
    static let maxAppealCount = 3

    /// AI 调用超时（秒）
    static let aiTimeoutInterval: TimeInterval = 60

    /// DeepSeek Reasoner 的额外超时宽限（秒）
    static let reasonerTimeoutInterval: TimeInterval = 180

    /// 计时器刷新间隔（秒）
    static let timerRefreshInterval: TimeInterval = 1.0

    /// 模型选择持久化 key
    static let selectedModelKey = "nlplan_selected_model"

    /// 外观模式持久化 key
    static let appearanceModeKey = "nlplan_appearance_mode"

    /// 默认模型
    static let defaultModel = "deepseek-chat"

    /// 可选文本模型列表（id, 显示名称, 描述）
    static let availableModels: [(id: String, name: String, description: String)] = [
        ("deepseek-chat",     "DeepSeek Chat",     "DeepSeek-V3 对话模式"),
        ("deepseek-reasoner", "DeepSeek Reasoner", "DeepSeek-V3 深度推理模式"),
    ]
}
