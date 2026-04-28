import Foundation
import SwiftData

/// 队列项解析状态
enum ParseStatus: String, Equatable {
    case waiting       // 排队中
    case processing    // AI 正在解析
    case completed     // 解析完成，等待用户确认
    case failed        // 解析失败
}

/// AI 解析队列项（SwiftData 持久化）
/// 确认后转为 IdeaEntity + ThoughtEntity，然后删除本实体
@Model
final class ParseQueueItemEntity {

    @Attribute(.unique) var id: UUID
    var rawText: String
    var status: String           // ParseStatus rawValue
    var parsedTasksData: Data?   // JSON 编码的 [ParsedTask]
    var errorMessage: String?
    var createdAt: Date
    var cumulativeInputTokens: Int?
    var cumulativeOutputTokens: Int?

    init(rawText: String) {
        self.id = UUID()
        self.rawText = rawText
        self.status = ParseStatus.waiting.rawValue
        self.parsedTasksData = nil
        self.errorMessage = nil
        self.createdAt = .now
        self.cumulativeInputTokens = 0
        self.cumulativeOutputTokens = 0
    }

    // MARK: - 计算属性

    var parseStatus: ParseStatus {
        get { ParseStatus(rawValue: status) ?? .waiting }
        set { status = newValue.rawValue }
    }

    var parsedTasks: [ParsedTask]? {
        get {
            guard let data = parsedTasksData else { return nil }
            return try? JSONDecoder().decode([ParsedTask].self, from: data)
        }
        set {
            if let newValue {
                parsedTasksData = try? JSONEncoder().encode(newValue)
            } else {
                parsedTasksData = nil
            }
        }
    }

    /// 用于队列列表显示的截断摘要
    var displaySummary: String {
        if rawText.count > 30 {
            return String(rawText.prefix(30)) + "..."
        }
        return rawText
    }
}
