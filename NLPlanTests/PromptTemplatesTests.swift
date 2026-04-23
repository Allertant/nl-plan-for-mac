import Testing
import Foundation
@testable import NLPlan

// MARK: - PromptTemplates Tests

@Suite("PromptTemplates Tests")
struct PromptTemplatesTests {

    @Test("parseThought 包含用户输入")
    func testParseThoughtContainsInput() {
        let prompt = PromptTemplates.parseThought(input: "今天要写文档", existingTaskTitles: [])
        #expect(prompt.contains("今天要写文档"))
    }

    @Test("parseThought 包含已有任务列表")
    func testParseThoughtContainsExistingTasks() {
        let prompt = PromptTemplates.parseThought(
            input: "跑步",
            existingTaskTitles: ["写文档", "开会"]
        )
        #expect(prompt.contains("写文档"))
        #expect(prompt.contains("开会"))
    }

    @Test("parseThought 无已有任务时不包含任务列表")
    func testParseThoughtNoExistingTasks() {
        let prompt = PromptTemplates.parseThought(input: "跑步", existingTaskTitles: [])
        #expect(!prompt.contains("用户已有的任务列表"))
    }

    @Test("dailyGrade 包含统计数据")
    func testDailyGradeContainsStats() {
        let input = DailySummaryInput(
            settlementDate: "2026年4月23日",
            totalTasks: 5,
            completedTasks: 4,
            totalPlannedMinutes: 240,
            totalActualMinutes: 265,
            deviationRate: 0.1,
            extraCompleted: 1,
            taskDetails: [
                TaskDetail(
                    title: "写文档",
                    estimatedMinutes: 60,
                    actualMinutes: 80,
                    completed: true,
                    priority: "high",
                    sourceType: "项目链接必做项",
                    note: "完成了核心结构"
                )
            ]
        )
        let prompt = PromptTemplates.dailyGrade(input: input)
        #expect(prompt.contains("5"))
        #expect(prompt.contains("4"))
        #expect(prompt.contains("写文档"))
        #expect(prompt.contains("2026年4月23日"))
        #expect(prompt.contains("项目链接必做项"))
        #expect(prompt.contains("high"))
        #expect(prompt.contains("完成了核心结构"))
        #expect(prompt.contains("完成率只是参考指标之一"))
        #expect(prompt.contains("少量高难任务"))
        #expect(prompt.contains("大量简单任务全部完成"))
        #expect(prompt.contains("无备注未完成"))
    }

    @Test("appealGrade 包含用户反馈")
    func testAppealGradeContainsFeedback() {
        let grade = DailyGrade(
            grade: .B,
            summary: "还不错",
            stats: GradeStats(totalTasks: 3, completedTasks: 2, totalPlannedMinutes: 120, totalActualMinutes: 130, deviationRate: 0.08, extraCompleted: 0),
            suggestion: "加油",
            gradingBasis: "完成率66%"
        )
        let input = DailySummaryInput(
            totalTasks: 3,
            completedTasks: 2,
            totalPlannedMinutes: 120,
            totalActualMinutes: 130,
            deviationRate: 0.08,
            extraCompleted: 0,
            taskDetails: []
        )
        let prompt = PromptTemplates.appealGrade(originalGrade: grade, originalInput: input, userFeedback: "我觉得应该更高")
        #expect(prompt.contains("我觉得应该更高"))
        #expect(prompt.contains("B"))
    }
}
