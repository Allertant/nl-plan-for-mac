import Foundation

/// 任务所在的池
enum TaskPool: String, Codable, CaseIterable, Sendable {
    case ideaPool = "idea_pool"
    case mustDo = "must_do"

    var displayName: String {
        switch self {
        case .ideaPool: return "想法池"
        case .mustDo: return "必做项"
        }
    }
}
