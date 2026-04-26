import Foundation

/// 任务状态
enum TaskStatus: String, Codable, CaseIterable, Sendable {
    case pending = "pending"
    case running = "running"
    case paused = "paused"
    case done = "done"

    var displayName: String {
        switch self {
        case .pending: return "待执行"
        case .running: return "执行中"
        case .paused: return "已暂停"
        case .done: return "已完成"
        }
    }

    var iconName: String {
        switch self {
        case .pending: return "circle"
        case .running: return "play.circle.fill"
        case .paused: return "pause.circle.fill"
        case .done: return "checkmark.circle.fill"
        }
    }
}
