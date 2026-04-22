import Testing
import Foundation
@testable import NLPlan

/// Mock AI 服务 — 用于测试
struct MockAIService: AIServiceProtocol {

    var mockParsedTasks: [ParsedTask] = []
    var mockGrade: DailyGrade?
    var shouldFail: Bool = false

    func parseThoughts(input: String, existingTaskTitles: [String]) async throws -> [ParsedTask] {
        if shouldFail {
            throw NLPlanError.aiServiceUnavailable
        }
        return mockParsedTasks
    }

    func refineTasks(originalInput: String, currentTasks: [ParsedTask], userInstruction: String) async throws -> [ParsedTask] {
        if shouldFail {
            throw NLPlanError.aiServiceUnavailable
        }
        return currentTasks
    }

    func generateDailyGrade(summaryInput: DailySummaryInput) async throws -> DailyGrade {
        if shouldFail {
            throw NLPlanError.aiServiceUnavailable
        }
        return mockGrade ?? DailyGrade(
            grade: .B,
            summary: "测试评分",
            stats: GradeStats(
                totalTasks: summaryInput.totalTasks,
                completedTasks: summaryInput.completedTasks,
                totalPlannedMinutes: summaryInput.totalPlannedMinutes,
                totalActualMinutes: summaryInput.totalActualMinutes,
                deviationRate: summaryInput.deviationRate,
                extraCompleted: summaryInput.extraCompleted
            ),
            suggestion: "测试建议",
            gradingBasis: "测试依据"
        )
    }

    func appealGrade(originalGrade: DailyGrade, originalInput: DailySummaryInput, userFeedback: String) async throws -> DailyGrade {
        if shouldFail {
            throw NLPlanError.aiServiceUnavailable
        }
        return DailyGrade(
            grade: .A,
            summary: "重新评分",
            stats: originalGrade.stats,
            suggestion: "新的建议",
            gradingBasis: "根据用户反馈重新评分"
        )
    }

    func recommendTasks(
        ideaPoolTasks: [TaskRecommendationInput],
        mustDoTasks: [TaskRecommendationInput],
        remainingHours: Double,
        strategy: MustDoViewModel.RecommendationStrategy
    ) async throws -> RecommendationResult {
        if shouldFail {
            throw NLPlanError.aiServiceUnavailable
        }
        return RecommendationResult(recommendations: [], overallReason: "测试推荐")
    }

    func cleanupIdeaPool(tasks: [TaskRecommendationInput]) async throws -> CleanupResult {
        if shouldFail {
            throw NLPlanError.aiServiceUnavailable
        }
        return CleanupResult(items: [], overallReason: "测试清理")
    }

    func classifyProjects(tasks: [ProjectClassificationInput]) async throws -> [ProjectClassification] {
        if shouldFail {
            throw NLPlanError.aiServiceUnavailable
        }
        return tasks.map { ProjectClassification(ideaId: $0.id, isProject: false, reason: "测试") }
    }

    func analyzeProjectProgress(projects: [ProjectProgressInput]) async throws -> [ProjectProgressAnalysis] {
        if shouldFail {
            throw NLPlanError.aiServiceUnavailable
        }
        return projects.map { ProjectProgressAnalysis(ideaId: $0.ideaId, progress: 0, summary: "测试进度") }
    }
}
