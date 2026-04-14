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
}
