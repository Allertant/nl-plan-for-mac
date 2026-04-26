import Foundation

/// 任务优先级
enum TaskPriority: String, Codable, CaseIterable, Sendable {
    case high = "high"
    case medium = "medium"
    case low = "low"

    var displayName: String {
        switch self {
        case .high: return "高"
        case .medium: return "中"
        case .low: return "低"
        }
    }

    var iconName: String {
        switch self {
        case .high: return "flag.fill"
        case .medium: return "flag"
        case .low: return "flag"
        }
    }

    var colorName: String {
        switch self {
        case .high: return "red"
        case .medium: return "orange"
        case .low: return "blue"
        }
    }
}
