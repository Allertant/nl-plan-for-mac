import Foundation

/// 全局常量
enum AppConstants {
    /// 应用标识
    static let appIdentifier = "com.nlplan.mac"

    /// Keychain key for API Key
    static let apiKeyKeychainKey = "nlplan_zhipu_api_key"

    /// 输入长度上限
    static let maxInputLength = 2000

    /// 申诉次数上限
    static let maxAppealCount = 3

    /// AI 调用超时（秒）
    static let aiTimeoutInterval: TimeInterval = 30

    /// 计时器刷新间隔（秒）
    static let timerRefreshInterval: TimeInterval = 1.0

    /// 模型选择持久化 key
    static let selectedModelKey = "nlplan_selected_model"

    /// 默认模型
    static let defaultModel = "glm-5.1"

    /// 可选文本模型列表（id, 显示名称, 描述）
    static let availableModels: [(id: String, name: String, description: String)] = [
        ("glm-5.1",       "GLM-5.1",         "最新旗舰"),
        ("glm-5",         "GLM-5",           "高智能基座"),
        ("glm-5-turbo",   "GLM-5-Turbo",     "龙虾增强基座"),
        ("glm-4.7",       "GLM-4.7",         "高智能模型"),
        ("glm-4.7-flashx","GLM-4.7-FlashX",  "轻量高速"),
        ("glm-4.6",       "GLM-4.6",         "超强性能"),
        ("glm-4.5-air",   "GLM-4.5-Air",     "高性价比"),
        ("glm-4.5-airx",  "GLM-4.5-AirX",    "高性价比极速版"),
        ("glm-4-long",    "GLM-4-Long",      "超长输入"),
        ("glm-4.7-flash", "GLM-4.7-Flash",   "免费模型"),
        ("glm-4-flash",   "GLM-4-Flash",     "免费高速"),
    ]
}
