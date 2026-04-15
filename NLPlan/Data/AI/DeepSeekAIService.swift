import Foundation

/// DeepSeek AI 服务实现
///
/// DeepSeek API 兼容 OpenAI 格式：
/// - 端点：https://api.deepseek.com/chat/completions
/// - 认证：Bearer Token
/// - 两种模式：deepseek-chat（普通对话）、deepseek-reasoner（深度推理）
final class DeepSeekAIService: AIServiceProtocol {

    private let apiKey: String
    private let endpoint: URL
    private let urlSession: URLSession
    private let model: String

    init(
        apiKey: String,
        endpoint: URL = URL(string: "https://api.deepseek.com/chat/completions")!,
        model: String = "deepseek-chat"
    ) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.model = model

        let config = URLSessionConfiguration.default
        let timeoutInterval = Self.timeoutInterval(for: model)
        config.timeoutIntervalForRequest = timeoutInterval
        config.timeoutIntervalForResource = timeoutInterval + 30
        self.urlSession = URLSession(configuration: config)
    }

    // MARK: - AIServiceProtocol

    func parseThoughts(
        input: String,
        existingTaskTitles: [String]
    ) async throws -> [ParsedTask] {
        let prompt = PromptTemplates.parseThought(
            input: input,
            existingTaskTitles: existingTaskTitles
        )
        let responseContent = try await sendRequest(systemPrompt: "你是一个任务管理助手，只输出 JSON 格式。", userPrompt: prompt)
        let parsedResponse = try parseJSON(responseContent, as: ParsedTasksResponse.self)

        return parsedResponse.tasks.map { dto in
            ParsedTask(
                title: dto.title,
                category: dto.category,
                estimatedMinutes: dto.estimatedMinutes,
                priority: TaskPriority(rawValue: dto.priority) ?? .medium,
                recommended: dto.recommended,
                reason: dto.reason
            )
        }
    }

    func generateDailyGrade(summaryInput: DailySummaryInput) async throws -> DailyGrade {
        let prompt = PromptTemplates.dailyGrade(input: summaryInput)
        let responseContent = try await sendRequest(systemPrompt: "你是一个效率教练，只输出 JSON 格式。", userPrompt: prompt)
        let gradeResponse = try parseJSON(responseContent, as: GradeResponse.self)

        return DailyGrade(
            grade: Grade(rawValue: gradeResponse.grade) ?? .D,
            summary: gradeResponse.summary,
            stats: GradeStats(
                totalTasks: gradeResponse.stats.totalTasks,
                completedTasks: gradeResponse.stats.completedTasks,
                totalPlannedMinutes: gradeResponse.stats.totalPlannedMinutes,
                totalActualMinutes: gradeResponse.stats.totalActualMinutes,
                deviationRate: gradeResponse.stats.deviationRate,
                extraCompleted: summaryInput.extraCompleted
            ),
            suggestion: gradeResponse.suggestion,
            gradingBasis: gradeResponse.gradingBasis
        )
    }

    func appealGrade(
        originalGrade: DailyGrade,
        originalInput: DailySummaryInput,
        userFeedback: String
    ) async throws -> DailyGrade {
        let prompt = PromptTemplates.appealGrade(
            originalGrade: originalGrade,
            originalInput: originalInput,
            userFeedback: userFeedback
        )
        let responseContent = try await sendRequest(systemPrompt: "你是一个效率教练，只输出 JSON 格式。请根据用户反馈重新评分。", userPrompt: prompt)
        let gradeResponse = try parseJSON(responseContent, as: GradeResponse.self)

        return DailyGrade(
            grade: Grade(rawValue: gradeResponse.grade) ?? .D,
            summary: gradeResponse.summary,
            stats: GradeStats(
                totalTasks: gradeResponse.stats.totalTasks,
                completedTasks: gradeResponse.stats.completedTasks,
                totalPlannedMinutes: gradeResponse.stats.totalPlannedMinutes,
                totalActualMinutes: gradeResponse.stats.totalActualMinutes,
                deviationRate: gradeResponse.stats.deviationRate,
                extraCompleted: originalInput.extraCompleted
            ),
            suggestion: gradeResponse.suggestion,
            gradingBasis: gradeResponse.gradingBasis
        )
    }

    // MARK: - Private

    private func sendRequest(systemPrompt: String, userPrompt: String) async throws -> String {
        let timeoutInterval = Self.timeoutInterval(for: model)
        let request = DeepSeekAPIRequest(
            model: model,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: userPrompt)
            ],
            temperature: 0.3,
            responseFormat: .init(type: "json_object")
        )

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        // 重试最多 2 次
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                let (data, response) = try await urlSession.data(for: urlRequest)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NLPlanError.aiServiceUnavailable
                }

                switch httpResponse.statusCode {
                case 200..<300:
                    let apiResponse = try JSONDecoder().decode(DeepSeekAPIResponse.self, from: data)
                    guard let content = apiResponse.choices.first?.message.content else {
                        throw NLPlanError.aiResponseParseError
                    }
                    return content
                case 401:
                    throw NLPlanError.aiAPIError(statusCode: httpResponse.statusCode, message: "API Key 无效")
                case 429:
                    throw NLPlanError.aiAPIError(statusCode: httpResponse.statusCode, message: "请求频率超限")
                default:
                    let message = String(data: data, encoding: .utf8) ?? "未知错误"
                    throw NLPlanError.aiAPIError(statusCode: httpResponse.statusCode, message: message)
                }
            } catch let urlError as URLError where urlError.code == .timedOut {
                print("⏳ DeepSeek \(model) 第 \(attempt + 1) 次请求超时（\(Int(timeoutInterval))s）")
                throw NLPlanError.aiRequestTimeout
            } catch let error as NLPlanError {
                throw error
            } catch {
                lastError = error
                print("⚠️ DeepSeek \(model) 第 \(attempt + 1) 次请求失败：\(error.localizedDescription)")
                if attempt < 2 {
                    try await Task.sleep(for: .seconds(3))
                }
            }
        }
        throw lastError ?? NLPlanError.aiRequestTimeout
    }

    private static func timeoutInterval(for model: String) -> TimeInterval {
        if model == "deepseek-reasoner" {
            return AppConstants.reasonerTimeoutInterval
        }
        return AppConstants.aiTimeoutInterval
    }

    private func parseJSON<T: Decodable>(_ jsonString: String, as type: T.Type) throws -> T {
        // 尝试提取 JSON（可能包含在 markdown code block 中）
        let cleanJSON = extractJSON(from: jsonString)
        guard let data = cleanJSON.data(using: .utf8) else {
            throw NLPlanError.aiResponseParseError
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw NLPlanError.aiResponseParseError
        }
    }

    /// 从可能包含 markdown code block 的文本中提取 JSON
    private func extractJSON(from text: String) -> String {
        // 尝试提取 ```json ... ``` 块
        if let range = text.range(of: "```json") {
            let afterBlock = text[range.upperBound...]
            if let endRange = afterBlock.range(of: "```") {
                return String(afterBlock[..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        // 尝试提取 ``` ... ``` 块
        if let range = text.range(of: "```") {
            let afterBlock = text[range.upperBound...]
            if let endRange = afterBlock.range(of: "```") {
                return String(afterBlock[..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        // 直接返回原文
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
