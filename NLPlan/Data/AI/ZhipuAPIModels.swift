import Foundation

// MARK: - API Request

struct ZhipuAPIRequest: Encodable {
    let model: String
    let messages: [ZhipuMessage]
    let temperature: Double
    let responseFormat: ResponseFormat?

    struct ZhipuMessage: Encodable {
        let role: String
        let content: String
    }

    struct ResponseFormat: Encodable {
        let type: String
    }
}

// MARK: - API Response

struct ZhipuAPIResponse: Decodable {
    let choices: [Choice]
    let usage: Usage?

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String
    }

    struct Usage: Decodable {
        let promptTokens: Int?
        let completionTokens: Int?
        let totalTokens: Int?

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }
}

// MARK: - Parsed Tasks Response (from AI JSON)

struct ParsedTasksResponse: Decodable {
    let tasks: [ParsedTaskDTO]
}

struct ParsedTaskDTO: Decodable {
    let title: String
    let category: String
    let estimatedMinutes: Int
    let priority: String
    let recommended: Bool
    let reason: String

    enum CodingKeys: String, CodingKey {
        case title, category, priority, recommended, reason
        case estimatedMinutes = "estimated_minutes"
    }
}

// MARK: - Grade Response (from AI JSON)

struct GradeResponse: Decodable {
    let grade: String
    let summary: String
    let gradingBasis: String
    let stats: GradeStatsDTO
    let suggestion: String

    enum CodingKeys: String, CodingKey {
        case grade, summary, stats, suggestion
        case gradingBasis = "grading_basis"
    }
}

struct GradeStatsDTO: Decodable {
    let totalTasks: Int
    let completedTasks: Int
    let totalPlannedMinutes: Int
    let totalActualMinutes: Int
    let deviationRate: Double

    enum CodingKeys: String, CodingKey {
        case totalTasks = "total_tasks"
        case completedTasks = "completed_tasks"
        case totalPlannedMinutes = "total_planned_minutes"
        case totalActualMinutes = "total_actual_minutes"
        case deviationRate = "deviation_rate"
    }
}
