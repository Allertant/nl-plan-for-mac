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

    /// 根据用户修改指令调整已解析的任务
    func refineTasks(
        originalInput: String,
        currentTasks: [ParsedTask],
        userInstruction: String
    ) async throws -> [ParsedTask]

    /// 日终评分
    /// - Parameter summaryInput: 当日任务完成数据
    /// - Returns: 评分结果
    func generateDailyGrade(
        summaryInput: DailySummaryInput
    ) async throws -> DailyGrade

    /// 从想法池中推荐今日待做任务
    /// - Parameters:
    ///   - ideaPoolTasks: 想法池中的全部任务
    ///   - mustDoTasks: 当前必做项列表
    ///   - remainingHours: 剩余可用工作小时数
    ///   - strategy: 推荐策略（快速 / 综合）
    /// - Returns: 推荐结果（按推荐顺序排列）
    func recommendTasks(
        ideaPoolTasks: [TaskRecommendationInput],
        mustDoTasks: [TaskRecommendationInput],
        remainingHours: Double,
        strategy: MustDoViewModel.RecommendationStrategy
    ) async throws -> RecommendationResult

    /// 驳斥评分：AI 根据用户反馈重新评分
    func appealGrade(
        originalGrade: DailyGrade,
        originalInput: DailySummaryInput,
        userFeedback: String
    ) async throws -> DailyGrade

    /// AI 清理想法池：推荐应删除的过时/不合适任务
    /// - Parameter tasks: 想法池中所有任务
    /// - Returns: 建议删除的任务列表及理由
    func cleanupIdeaPool(tasks: [TaskRecommendationInput]) async throws -> CleanupResult

    /// 判断哪些想法属于项目型条目
    func classifyProjects(tasks: [ProjectClassificationInput]) async throws -> [ProjectClassification]

    /// 基于来源绑定的必做项分析项目进度
    func analyzeProjectProgress(projects: [ProjectProgressInput]) async throws -> [ProjectProgressAnalysis]

    /// 为项目生成外部研究提示词，供联网 AI 产出结构化规划背景
    func generatePlanningBackgroundPrompt(
        input: PlanningBackgroundPromptInput
    ) async throws -> PlanningBackgroundPromptResult
}
