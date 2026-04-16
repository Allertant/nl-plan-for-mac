import Testing
import Foundation
@testable import NLPlan

// MARK: - MockAI Service Tests

@Suite("MockAIService Tests")
struct MockAIServiceTests {

    @Test("成功解析想法")
    func testParseThoughtsSuccess() async throws {
        let mockService = MockAIService(
            mockParsedTasks: [
                ParsedTask(title: "写文档", category: "工作", estimatedMinutes: 60, recommended: true, reason: "紧急"),
                ParsedTask(title: "跑步", category: "生活", estimatedMinutes: 30, recommended: false, reason: "不紧急")
            ]
        )

        let result = try await mockService.parseThoughts(input: "今天要写文档和跑步", existingTaskTitles: [])
        #expect(result.count == 2)
        #expect(result[0].title == "写文档")
        #expect(result[0].recommended == true)
        #expect(result[1].title == "跑步")
    }

    @Test("解析失败时抛出错误")
    func testParseThoughtsFailure() async {
        let mockService = MockAIService(shouldFail: true)

        do {
            _ = try await mockService.parseThoughts(input: "test", existingTaskTitles: [])
            #expect(Bool(false), "应该抛出错误")
        } catch {
            #expect(error is NLPlanError)
        }
    }

    @Test("日终评分成功")
    func testDailyGradeSuccess() async throws {
        let mockGrade = DailyGrade(
            grade: .A,
            summary: "做得好",
            stats: GradeStats(totalTasks: 5, completedTasks: 5, totalPlannedMinutes: 240, totalActualMinutes: 250, deviationRate: 0.04, extraCompleted: 0),
            suggestion: "继续保持",
            gradingBasis: "全部完成"
        )
        let mockService = MockAIService(mockGrade: mockGrade)

        let input = DailySummaryInput(
            totalTasks: 5,
            completedTasks: 5,
            totalPlannedMinutes: 240,
            totalActualMinutes: 250,
            deviationRate: 0.04,
            extraCompleted: 0,
            taskDetails: []
        )

        let result = try await mockService.generateDailyGrade(summaryInput: input)
        #expect(result.grade == .A)
        #expect(result.summary == "做得好")
    }

    @Test("驳斥评分成功")
    func testAppealGradeSuccess() async throws {
        let mockService = MockAIService()

        let originalGrade = DailyGrade(
            grade: .B,
            summary: "还不错",
            stats: GradeStats(totalTasks: 3, completedTasks: 2, totalPlannedMinutes: 120, totalActualMinutes: 130, deviationRate: 0.08, extraCompleted: 0),
            suggestion: "加油",
            gradingBasis: "完成率66%"
        )

        let originalInput = DailySummaryInput(
            totalTasks: 3,
            completedTasks: 2,
            totalPlannedMinutes: 120,
            totalActualMinutes: 130,
            deviationRate: 0.08,
            extraCompleted: 0,
            taskDetails: []
        )

        let result = try await mockService.appealGrade(
            originalGrade: originalGrade,
            originalInput: originalInput,
            userFeedback: "我觉得应该更高"
        )
        #expect(result.grade == .A) // Mock 返回 A
    }
}

// MARK: - DayStats Tests

@Suite("DayStats Tests")
struct DayStatsTests {

    @Test("完成率计算正确")
    func testCompletionRate() {
        let stats = DayStats(
            totalTasks: 5,
            completedTasks: 3,
            totalPlannedMinutes: 240,
            totalActualMinutes: 250,
            deviationRate: 0.04,
            extraCompleted: 0
        )
        #expect(stats.completionRate == 0.6)
    }

    @Test("零任务完成率为 0")
    func testZeroTaskCompletionRate() {
        let stats = DayStats(
            totalTasks: 0,
            completedTasks: 0,
            totalPlannedMinutes: 0,
            totalActualMinutes: 0,
            deviationRate: 0,
            extraCompleted: 0
        )
        #expect(stats.completionRate == 0)
    }

    @Test("降级评分正确")
    func testFallbackGrade() {
        let stats = DayStats(
            totalTasks: 4,
            completedTasks: 4,
            totalPlannedMinutes: 200,
            totalActualMinutes: 210,
            deviationRate: 0.05,
            extraCompleted: 0
        )
        #expect(stats.fallbackGrade == .A)
    }
}

// MARK: - DailySummaryInput Tests

@Suite("DailySummaryInput Tests")
struct DailySummaryInputTests {

    @Test("completionRate 计算正确")
    func testCompletionRate() {
        let input = DailySummaryInput(
            totalTasks: 10,
            completedTasks: 7,
            totalPlannedMinutes: 300,
            totalActualMinutes: 280,
            deviationRate: 0.07,
            extraCompleted: 0,
            taskDetails: []
        )
        #expect(abs(input.completionRate - 0.7) < 0.001)
    }
}

// MARK: - ParsedTask Tests

@Suite("ParsedTask Tests")
struct ParsedTaskTests {

    @Test("ParsedTask 创建正确")
    func testCreation() {
        let task = ParsedTask(
            title: "写文档",
            category: "工作",
            estimatedMinutes: 60,
            recommended: true,
            reason: "紧急"
        )
        #expect(task.title == "写文档")
        #expect(task.category == "工作")
        #expect(task.estimatedMinutes == 60)
        #expect(task.recommended == true)
    }
}
