import Foundation

/// 全局常量
enum AppConstants {
    /// 应用标识
    static let appIdentifier = "com.nlplan.mac"

    /// 旧版本使用过的 UserDefaults 偏好域
    static let legacyPreferencesDomain = "NLPlan"

    /// 伪安全存储前缀（当前使用 UserDefaults + Base64）
    static let secureStoragePrefix = "com.nlplan.mac.secure."

    /// Keychain key for API Key
    static let apiKeyKeychainKey = "nlplan_deepseek_api_key"

    /// 输入长度上限
    static let maxInputLength = 2000

    /// 申诉次数上限
    static let maxAppealCount = 3

    /// AI 调用超时（秒）
    static let aiTimeoutInterval: TimeInterval = 60

    /// 深度推理请求的额外超时宽限（秒）
    static let extendedReasoningTimeoutInterval: TimeInterval = 180

    /// 计时器刷新间隔（秒）
    static let timerRefreshInterval: TimeInterval = 1.0

    /// 模型选择持久化 key
    static let selectedModelKey = "nlplan_selected_model"

    /// 推理等级持久化 key
    static let selectedReasoningEffortKey = "nlplan_selected_reasoning_effort"

    /// 外观模式持久化 key
    static let appearanceModeKey = "nlplan_appearance_mode"

    /// 工作结束时间持久化 key
    static let workEndTimeKey = "nlplan_work_end_time"

    /// 并行计时持久化 key
    static let allowParallelKey = "nlplan_allow_parallel"

    /// 重启后暂停计时持久化 key
    static let pauseOnRestartKey = "nlplan_pause_on_restart"

    /// 推理模式持久化 key
    static let thinkingModeKey = "nlplan_thinking_mode"

    /// 自定义标签持久化 key
    static let tagsKey = "nlplan_custom_tags"

    /// 默认标签列表
    static let defaultTags = ["工作", "生活", "学习", "健康", "技术", "其他"]

    /// 默认工作结束时间（小时）
    static let defaultWorkEndHour: Double = 18.0

    /// 默认模型
    static let defaultModel = "deepseek-v4-pro"

    /// 可选文本模型列表（id, 显示名称, 描述）
    static let availableModels: [(id: String, name: String, description: String)] = [
        ("deepseek-v4-pro", "DeepSeek V4 Pro", "高质量推理与复杂任务"),
        ("deepseek-v4-flash", "DeepSeek V4 Flash", "更快响应与更低成本"),
    ]

    /// 默认推理等级
    static let defaultReasoningEffort = "high"

    /// 可选推理等级列表（id, 显示名称, 描述）
    static let availableReasoningEfforts: [(id: String, name: String, description: String)] = [
        ("high", "标准推理", "适合日常任务与稳定输出"),
        ("max", "深度推理", "适合复杂任务与更强思考"),
    ]

    static func normalizedModel(_ model: String?) -> String {
        switch model {
        case "deepseek-v4-pro", "deepseek-v4-flash":
            return model!
        case "deepseek-reasoner":
            return "deepseek-v4-pro"
        case "deepseek-chat":
            return "deepseek-v4-flash"
        default:
            return defaultModel
        }
    }

    static func normalizedReasoningEffort(_ effort: String?) -> String {
        switch effort {
        case "high", "max":
            return effort!
        case "low", "medium":
            return "high"
        case "xhigh":
            return "max"
        default:
            return defaultReasoningEffort
        }
    }
}
