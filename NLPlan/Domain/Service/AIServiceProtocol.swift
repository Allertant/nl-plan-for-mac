import Foundation

/// AI 服务抽象协议 — 所有 AI 实现必须遵循
protocol AIServiceProtocol: Sendable {
    /// 解析自然语言为结构化任务列表
    /// - Parameters:
    ///   - input: 用户原始输入文本
    ///   - existingTasks: 想法池中已有任务标题（用于去重）
    /// - Returns: 解析后的任务列表
    func parseThoughts(
        input: String,
        existingTaskTitles: [String]
    ) async throws -> [ParsedTask]

    /// 日终评分
    /// - Parameter summaryInput: 当日任务完成数据
    /// - Returns: 评分结果
    func generateDailyGrade(
        summaryInput: DailySummaryInput
    ) async throws -> DailyGrade

    /// 驳斥评分：AI 根据用户反馈重新评分
    /// - Parameters:
    ///   - originalGrade: 原始评分结果
    ///   - originalInput: 原始评分输入数据
    ///   - userFeedback: 用户驳斥理由
    /// - Returns: 重新评分结果（含评分依据）
    func appealGrade(
        originalGrade: DailyGrade,
        originalInput: DailySummaryInput,
        userFeedback: String
    ) async throws -> DailyGrade
}
