import Foundation

/// 应用错误域
enum NLPlanError: LocalizedError {
    // 输入错误
    case emptyInput
    case inputTooLong(max: Int)

    // AI 服务错误
    case aiServiceUnavailable
    case aiRequestTimeout
    case aiResponseParseError
    case aiAPIError(statusCode: Int, message: String)

    // 数据错误
    case dataSaveFailed(underlying: Error)
    case dataNotFound(entity: String, id: UUID)

    // 同步错误
    case notesSyncFailed(underlying: Error)

    // 网络错误
    case networkUnavailable

    // 业务错误
    case appealLimitExceeded
    case taskNotInExpectedPool(expected: TaskPool, actual: TaskPool)
    case apiKeyNotConfigured

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "请输入内容后再提交"
        case .inputTooLong(let max):
            return "输入内容不能超过 \(max) 个字符"
        case .aiServiceUnavailable:
            return "AI 服务暂时不可用，请稍后重试"
        case .aiRequestTimeout:
            return "AI 服务响应超时，请稍后重试"
        case .aiResponseParseError:
            return "AI 解析失败，请尝试重新描述"
        case .aiAPIError(_, let message):
            return "AI 服务错误：\(message)"
        case .dataSaveFailed(let error):
            return "数据保存失败：\(error.localizedDescription)"
        case .dataNotFound(let entity, let id):
            return "未找到 \(entity)：\(id)"
        case .notesSyncFailed(let error):
            return "同步到备忘录失败：\(error.localizedDescription)"
        case .networkUnavailable:
            return "网络不可用，请检查网络连接"
        case .appealLimitExceeded:
            return "今日申诉次数已达上限（3次）"
        case .taskNotInExpectedPool(let expected, let actual):
            return "任务不在预期池中（预期：\(expected.displayName)，实际：\(actual.displayName)）"
        case .apiKeyNotConfigured:
            return "请先配置 API Key"
        }
    }
}
