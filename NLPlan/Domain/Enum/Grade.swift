import Foundation

/// 日终评分等级
enum Grade: String, Codable, CaseIterable, Sendable {
    case S = "S"
    case A = "A"
    case B = "B"
    case C = "C"
    case D = "D"

    var displayName: String {
        rawValue
    }

    /// 基于完成率的规则化评分（降级方案，AI 不可用时使用）
    static func fromCompletionRate(_ rate: Double) -> Grade {
        switch rate {
        case 1.0: return .A
        case 0.8..<1.0: return .B
        case 0.5..<0.8: return .C
        default: return .D
        }
    }
}
