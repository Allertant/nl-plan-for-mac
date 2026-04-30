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
    private(set) var lastTokenUsage: TokenUsage?

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
        let tags = UserDefaults.standard.stringArray(forKey: AppConstants.tagsKey) ?? AppConstants.defaultTags
        let prompt = PromptTemplates.parseThought(
            input: input,
            existingTaskTitles: existingTaskTitles,
            availableTags: tags
        )
        let parsedResponse = try await requestAndParse(
            systemPrompt: "你是一个任务管理助手，只输出 JSON 格式。",
            userPrompt: prompt,
            as: ParsedTasksResponse.self
        )

        return parsedResponse.tasks.map { dto in
            let (deadline, hasExplicitYear, hasTime) = Self.parseDeadlineString(dto.deadline)
            return ParsedTask(
                title: dto.title,
                category: dto.category,
                estimatedMinutes: dto.estimatedMinutes,
                recommended: dto.recommended ?? false,
                reason: dto.reason ?? "",
                isProject: dto.isProject,
                note: dto.note,
                deadline: deadline,
                deadlineHasExplicitYear: hasExplicitYear,
                deadlineHasTime: hasTime
            )
        }
    }

    func refineTasks(
        originalInput: String,
        currentTasks: [ParsedTask],
        userInstruction: String
    ) async throws -> [ParsedTask] {
        let tags = UserDefaults.standard.stringArray(forKey: AppConstants.tagsKey) ?? AppConstants.defaultTags
        let prompt = PromptTemplates.refineParsedTasks(
            originalInput: originalInput,
            currentTasks: currentTasks,
            userInstruction: userInstruction,
            availableTags: tags
        )
        let parsedResponse = try await requestAndParse(
            systemPrompt: "你是一个任务管理助手，只输出 JSON 格式。",
            userPrompt: prompt,
            as: ParsedTasksResponse.self
        )

        return parsedResponse.tasks.map { dto in
            let (deadline, hasExplicitYear, hasTime) = Self.parseDeadlineString(dto.deadline)
            return ParsedTask(
                title: dto.title,
                category: dto.category,
                estimatedMinutes: dto.estimatedMinutes,
                recommended: dto.recommended ?? false,
                reason: dto.reason ?? "",
                isProject: dto.isProject,
                note: dto.note,
                deadline: deadline,
                deadlineHasExplicitYear: hasExplicitYear,
                deadlineHasTime: hasTime
            )
        }
    }

    func generateDailyGrade(summaryInput: DailySummaryInput) async throws -> DailyGrade {
        let prompt = PromptTemplates.dailyGrade(input: summaryInput)
        let gradeResponse = try await requestAndParse(
            systemPrompt: "你是一个效率教练，只输出 JSON 格式。",
            userPrompt: prompt,
            as: GradeResponse.self
        )

        return DailyGrade(
            grade: Grade(rawValue: gradeResponse.grade) ?? .F,
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
        let gradeResponse = try await requestAndParse(
            systemPrompt: "你是一个效率教练，只输出 JSON 格式。请根据用户反馈重新评分。",
            userPrompt: prompt,
            as: GradeResponse.self
        )

        return DailyGrade(
            grade: Grade(rawValue: gradeResponse.grade) ?? .F,
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

    func recommendTasks(
        ideaPoolTasks: [TaskRecommendationInput],
        mustDoTasks: [TaskRecommendationInput],
        remainingHours: Double,
        strategy: MustDoViewModel.RecommendationStrategy,
        extraContext: String? = nil
    ) async throws -> RecommendationResult {
        let prompt = PromptTemplates.recommendTasks(
            ideaPoolTasks: ideaPoolTasks,
            mustDoTasks: mustDoTasks,
            remainingHours: remainingHours,
            strategy: strategy,
            extraContext: extraContext
        )
        let response = try await requestAndParse(
            systemPrompt: "你是一个任务管理助手，只输出 JSON 格式。",
            userPrompt: prompt,
            as: RecommendationResponse.self
        )

        let recommendations = response.recommendations.compactMap { dto -> TaskRecommendation? in
            let taskId = dto.taskId.flatMap(UUID.init(uuidString:))
            let sourceIdeaId = dto.sourceIdeaId.flatMap(UUID.init(uuidString:))
            guard taskId != nil || sourceIdeaId != nil else { return nil }
            return TaskRecommendation(
                taskId: taskId,
                sourceIdeaId: sourceIdeaId,
                arrangementId: nil,
                title: dto.title,
                category: dto.category,
                estimatedMinutes: dto.estimatedMinutes,
                reason: dto.reason
            )
        }

        return RecommendationResult(
            recommendations: recommendations,
            overallReason: response.overallReason
        )
    }

    func cleanupIdeaPool(tasks: [TaskRecommendationInput]) async throws -> CleanupResult {
        let prompt = PromptTemplates.cleanupIdeaPool(tasks: tasks)
        let response = try await requestAndParse(
            systemPrompt: "你是一个任务管理助手，只输出 JSON 格式。",
            userPrompt: prompt,
            as: CleanupResponse.self
        )

        let items = response.items.compactMap { dto -> CleanupSuggestion? in
            guard let uuid = UUID(uuidString: dto.taskId) else { return nil }
            return CleanupSuggestion(taskId: uuid, reason: dto.reason)
        }

        return CleanupResult(items: items, overallReason: response.overallReason)
    }

    func classifyProjects(tasks: [ProjectClassificationInput]) async throws -> [ProjectClassification] {
        let prompt = PromptTemplates.classifyProjects(tasks: tasks)
        let response = try await requestAndParse(
            systemPrompt: "你是一个任务管理助手，只输出 JSON 格式。",
            userPrompt: prompt,
            as: ProjectClassificationResponse.self
        )

        return response.items.compactMap { item in
            guard let ideaId = UUID(uuidString: item.ideaId) else { return nil }
            return ProjectClassification(ideaId: ideaId, isProject: item.isProject, reason: item.reason)
        }
    }

    func analyzeProjectProgress(projects: [ProjectProgressInput]) async throws -> [ProjectProgressAnalysis] {
        let prompt = PromptTemplates.analyzeProjectProgress(projects: projects)
        let response = try await requestAndParse(
            systemPrompt: "你是一个任务管理助手，只输出 JSON 格式。",
            userPrompt: prompt,
            as: ProjectProgressResponse.self
        )

        return response.items.compactMap { item in
            guard let ideaId = UUID(uuidString: item.ideaId) else { return nil }
            return ProjectProgressAnalysis(
                ideaId: ideaId,
                progress: item.progress,
                summary: item.summary
            )
        }
    }

    func generateProjectRecommendationSummary(
        input: ProjectRecommendationSummaryInput
    ) async throws -> ProjectRecommendationSummaryResult {
        let prompt = PromptTemplates.generateProjectRecommendationSummary(input: input)
        let response = try await requestAndParse(
            systemPrompt: "你是一个项目状态摘要助手，只输出 JSON 格式。",
            userPrompt: prompt,
            as: ProjectRecommendationSummaryResponse.self
        )

        return ProjectRecommendationSummaryResult(summary: response.summary)
    }

    func generatePlanningBackgroundPrompt(
        input: PlanningBackgroundPromptInput
    ) async throws -> PlanningBackgroundPromptResult {
        let prompt = PromptTemplates.generatePlanningBackgroundPrompt(input: input)
        let response = try await requestAndParse(
            systemPrompt: "你是一个任务规划助手，只输出 JSON 格式。",
            userPrompt: prompt,
            as: PlanningBackgroundPromptResponse.self
        )

        return PlanningBackgroundPromptResult(
            reason: response.reason,
            researchPrompt: response.researchPrompt
        )
    }

    // MARK: - Deadline Parsing

    /// 解析 AI 返回的截止时间字符串
    /// 格式: "M-d" | "M-d HH:mm" | "yyyy-M-d" | "yyyy-M-d HH:mm"
    /// 返回: (date, hasExplicitYear, hasTime)
    static func parseDeadlineString(_ string: String?) -> (Date?, Bool, Bool) {
        guard let string, !string.trimmingCharacters(in: .whitespaces).isEmpty else {
            // 无截止时间 → 默认今天
            return (Calendar.current.startOfDay(for: .now), false, false)
        }

        let trimmed = string.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
        let datePart = String(parts[0])
        let timePart = parts.count > 1 ? String(parts[1]) : nil

        let dateComponents = datePart.split(separator: "-", omittingEmptySubsequences: true).compactMap { Int($0) }
        let cal = Calendar.current
        let now = Date()

        var year: Int, month: Int, day: Int
        let hasExplicitYear: Bool

        if dateComponents.count >= 3 {
            year = dateComponents[0]
            month = dateComponents[1]
            day = dateComponents[2]
            hasExplicitYear = true
        } else if dateComponents.count == 2 {
            year = cal.component(.year, from: now)
            month = dateComponents[0]
            day = dateComponents[1]
            hasExplicitYear = false
        } else {
            return (cal.startOfDay(for: now), false, false)
        }

        var hour = 0, minute = 0
        let hasTime: Bool
        if let timePart {
            let timeComponents = timePart.split(separator: ":").compactMap { Int($0) }
            if timeComponents.count >= 2 {
                hour = timeComponents[0]
                minute = timeComponents[1]
                hasTime = true
            } else if timeComponents.count == 1 {
                hour = timeComponents[0]
                hasTime = true
            } else {
                hasTime = false
            }
        } else {
            hasTime = false
        }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute

        let date = cal.date(from: components) ?? cal.startOfDay(for: now)
        return (date, hasExplicitYear, hasTime)
    }

    // MARK: - Private

    /// 发送请求并解析 JSON，失败时携带原始响应和错误信息重试一次
    private func requestAndParse<T: Decodable>(
        systemPrompt: String,
        userPrompt: String,
        as type: T.Type
    ) async throws -> T {
        let raw = try await sendRequest(systemPrompt: systemPrompt, userPrompt: userPrompt)

        do {
            return try parseJSON(raw, as: type)
        } catch {
            // 解析失败，构建纠错 prompt 重试一次
            print("⚠️ JSON 解析失败，尝试纠错重试。错误：\(error.localizedDescription)")
            let correctionPrompt = buildCorrectionPrompt(rawResponse: raw, parseError: error)
            let secondRaw = try await sendRequest(
                systemPrompt: "请修正你上一次返回的 JSON，只输出完整的正确 JSON，不要解释。",
                userPrompt: correctionPrompt
            )
            return try parseJSON(secondRaw, as: type)
        }
    }

    /// 构建纠错 prompt：将原始响应和错误信息发送给 AI
    private func buildCorrectionPrompt(rawResponse: String, parseError: Error) -> String {
        """
        你上一次返回的内容解析失败，请修正后重新输出。

        ## 你上次的返回内容
        \(rawResponse)

        ## 解析失败的错误信息
        \(parseError.localizedDescription)

        ## 要求
        请根据错误信息修正，只返回完整的正确 JSON，不要添加任何解释。
        """
    }

    private func sendRequest(systemPrompt: String, userPrompt: String) async throws -> String {
        try Task.checkCancellation()

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
            try Task.checkCancellation()
            do {
                let result: (Data, URLResponse) = try await withTaskCancellationHandler {
                    try await urlSession.data(for: urlRequest)
                } onCancel: {
                    // Task 取消时，URLSession data task 不会被自动取消。
                    // 通过取消当前请求来释放网络资源。
                    urlSession.getAllTasks { tasks in
                        tasks.forEach { $0.cancel() }
                    }
                }

                let (data, response) = result

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NLPlanError.aiServiceUnavailable
                }

                switch httpResponse.statusCode {
                case 200..<300:
                    let apiResponse = try JSONDecoder().decode(DeepSeekAPIResponse.self, from: data)
                    if let usage = apiResponse.usage {
                        lastTokenUsage = TokenUsage(
                            inputTokens: usage.promptTokens ?? 0,
                            outputTokens: usage.completionTokens ?? 0
                        )
                    }
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
            } catch let urlError as URLError where urlError.code == .cancelled {
                throw CancellationError()
            } catch let error as NLPlanError {
                throw error
            } catch is CancellationError {
                throw CancellationError()
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
        } catch let decodingError {
            print("❌ JSON 解码失败：\(decodingError)")
            throw decodingError
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
