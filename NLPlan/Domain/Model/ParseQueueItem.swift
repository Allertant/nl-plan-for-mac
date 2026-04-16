import Foundation

/// 队列项解析状态
enum ParseStatus: Equatable {
    case waiting       // 排队中
    case processing    // AI 正在解析
    case completed     // 解析完成，等待用户确认
    case failed        // 解析失败
}

/// AI 解析队列中的单个项
@Observable
final class ParseQueueItem: Identifiable {
    let id: UUID
    let rawText: String
    var status: ParseStatus
    var parsedTasks: [ParsedTask]?
    var errorMessage: String?
    let createdAt: Date

    /// 用于队列列表显示的截断摘要
    var displaySummary: String {
        if rawText.count > 30 {
            return String(rawText.prefix(30)) + "..."
        }
        return rawText
    }

    init(rawText: String) {
        self.id = UUID()
        self.rawText = rawText
        self.status = .waiting
        self.parsedTasks = nil
        self.errorMessage = nil
        self.createdAt = .now
    }
}
