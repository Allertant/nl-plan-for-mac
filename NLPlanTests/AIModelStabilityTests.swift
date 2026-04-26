import Testing
import Foundation
@testable import NLPlanKit

// MARK: - DeepSeek AI 模型接口稳定性测试
//
// 测试目的：验证 DeepSeek 各模型在实际 API 调用下的稳定性
// 测试内容：
//   1. 各模型 parseThoughts 接口可用性和响应格式正确性
//   2. 各模型 generateDailyGrade 接口可用性和响应格式正确性
//   3. 各模型 appealGrade 接口可用性和响应格式正确性
//   4. 多次调用同一模型的稳定性（响应一致性）
//   5. 无效 API Key 的错误处理
//
// 运行方式：
//   1. 复制 .env.example 为 .env 并填入真实 API Key
//      cp .env.example .env
//   2. 运行测试（自动从 .env 读取 Key）：
//      swift test --filter AIModelStability
//
// 也可直接通过环境变量传入：
//   NLPLAN_API_KEY=你的密钥 swift test --filter AIModelStability

// MARK: - 测试配置

/// 测试用的示例输入
private enum TestFixtures {

    /// 想法解析的示例输入
    static let sampleThoughtInput = "今天要完成项目报告，大概需要2小时。下午3点有个团队会议，半小时。晚上想跑步30分钟，再读一章书大概45分钟。"

    /// 日终评分的示例输入
    static let sampleSummaryInput = DailySummaryInput(
        totalTasks: 4,
        completedTasks: 3,
        totalPlannedMinutes: 195,
        totalActualMinutes: 210,
        deviationRate: 0.077,
        extraCompleted: 1,
        taskDetails: [
            TaskDetail(title: "写项目报告", estimatedMinutes: 120, actualMinutes: 130, completed: true),
            TaskDetail(title: "团队会议", estimatedMinutes: 30, actualMinutes: 45, completed: true),
            TaskDetail(title: "跑步", estimatedMinutes: 30, actualMinutes: 25, completed: true),
            TaskDetail(title: "读书", estimatedMinutes: 45, actualMinutes: 0, completed: false),
        ]
    )

    /// 驳斥评分的示例数据
    static let sampleOriginalGrade = DailyGrade(
        grade: .B,
        summary: "完成了大部分任务，但读书任务未完成",
        stats: GradeStats(
            totalTasks: 4,
            completedTasks: 3,
            totalPlannedMinutes: 195,
            totalActualMinutes: 210,
            deviationRate: 0.077,
            extraCompleted: 1
        ),
        suggestion: "明天注意时间安排",
        gradingBasis: "完成率75%，时间偏差7.7%"
    )

    /// 测试反馈文本
    static let sampleAppealFeedback = "我额外完成了想法池里的一个任务，应该得到更高的评分"

    /// 读取 API Key，按以下优先级：
    ///   1. 环境变量 NLPLAN_API_KEY
    ///   2. 项目根目录 .env 文件中的 NLPLAN_API_KEY
    ///   3. 应用 UserDefaults（KeychainStore）
    static func getAPIKey() throws -> String {
        // 1. 环境变量
        if let envKey = ProcessInfo.processInfo.environment["NLPLAN_API_KEY"], !envKey.isEmpty {
            return envKey
        }
        // 2. .env 文件
        if let dotEnvKey = Self.loadDotEnv()?.nlplanAPIKey, !dotEnvKey.isEmpty {
            return dotEnvKey
        }
        // 3. 应用 UserDefaults
        if let storedKey = KeychainStore.shared.load(key: AppConstants.apiKeyKeychainKey), !storedKey.isEmpty {
            return storedKey
        }
        throw NLPlanError.apiKeyNotConfigured
    }

    /// 从项目根目录的 .env 文件中读取配置
    private static func loadDotEnv() -> DotEnvConfig? {
        let fileManager = FileManager.default
        let currentPath = fileManager.currentDirectoryPath
        let envPath = currentPath + "/.env"

        guard let content = try? String(contentsOfFile: envPath, encoding: .utf8) else {
            return nil
        }

        var apiKey: String?
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.components(separatedBy: "=")
            guard parts.count >= 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1...].joined(separator: "=").trimmingCharacters(in: .whitespaces)
            if key == "NLPLAN_API_KEY" {
                apiKey = value
            }
        }

        guard let apiKey = apiKey else { return nil }
        return DotEnvConfig(nlplanAPIKey: apiKey)
    }

    /// .env 文件解析结果
    private struct DotEnvConfig {
        let nlplanAPIKey: String
    }
}

// MARK: - 全部稳定性测试（已弃用，默认禁用，避免产生 API 费用）

@Suite("DeepSeek AI 模型稳定性测试", .serialized, .disabled("Deprecated: avoid paid API calls in routine test runs"))
struct AIModelStabilityTests {

    // MARK: - 环境检查

    @Test("环境检查：API Key 已配置")
    func testAPIKeyConfigured() throws {
        do {
            let key = try TestFixtures.getAPIKey()
            let masked = key.count > 8
                ? key.prefix(4) + "****" + key.suffix(4)
                : "****"
            print("✅ API Key 已配置: \(masked)")
        } catch {
            print("⚠️ 未检测到 API Key，请通过以下方式之一配置：")
            print("⚠️   方式1: cp .env.example .env  # 然后填入真实 Key")
            print("⚠️   方式2: NLPLAN_API_KEY=你的密钥 swift test --filter AIModelStability")
            #expect(Bool(false), "未配置 API Key")
        }
    }

    @Test("环境检查：可用模型列表不为空")
    func testAvailableModelsNotEmpty() {
        #expect(!AppConstants.availableModels.isEmpty, "可用模型列表为空")
        print("✅ 可用模型数量: \(AppConstants.availableModels.count)")
        for model in AppConstants.availableModels {
            print("  - \(model.name) (\(model.id)): \(model.description)")
        }
    }

    // MARK: - parseThoughts 稳定性

    @Test("parseThoughts：各模型接口可用性")
    func testParseThoughtsAllModels() async throws {
        let apiKey = try TestFixtures.getAPIKey()

        for modelConfig in AppConstants.availableModels {
            print("📡 测试 parseThoughts: \(modelConfig.name) (\(modelConfig.id))")

            let service = DeepSeekAIService(apiKey: apiKey, model: modelConfig.id)

            do {
                let results = try await service.parseThoughts(
                    input: TestFixtures.sampleThoughtInput,
                    existingTaskTitles: []
                )

                #expect(!results.isEmpty, "\(modelConfig.name) 返回了空任务列表")

                for task in results {
                    #expect(!task.title.isEmpty, "\(modelConfig.name) 返回了空标题的任务")
                    if let estimatedMinutes = task.estimatedMinutes {
                        #expect(estimatedMinutes > 0, "\(modelConfig.name) 返回了预估时间为0的任务: \(task.title)")
                    }
                }

                print("  ✅ \(modelConfig.name): 返回 \(results.count) 个任务")
            } catch let error as NLPlanError {
                if case .aiAPIError(let statusCode, _) = error, statusCode == 429 {
                    print("  ⚠️ \(modelConfig.name): 限流 (429)，等待 5 秒后继续")
                    try await Task.sleep(for: .seconds(5))
                    continue
                }
                print("  ❌ \(modelConfig.name): 失败 - \(error.errorDescription ?? error.localizedDescription)")
                throw error
            }

            try await Task.sleep(for: .seconds(3))
        }
    }

    @Test("parseThoughts：返回数据结构完整性")
    func testParseThoughtsResponseStructure() async throws {
        let apiKey = try TestFixtures.getAPIKey()
        let service = DeepSeekAIService(apiKey: apiKey, model: AppConstants.defaultModel)

        let results = try await service.parseThoughts(
            input: TestFixtures.sampleThoughtInput,
            existingTaskTitles: ["已有任务A"]
        )

        for (index, task) in results.enumerated() {
            #expect(!task.title.isEmpty, "任务[\(index)] 标题为空")
            #expect(!task.category.isEmpty, "任务[\(index)] 分类为空: \(task.title)")
            if let estimatedMinutes = task.estimatedMinutes {
                #expect(estimatedMinutes > 0, "任务[\(index)] 预估时间 ≤ 0: \(task.title)")
            }
            #expect(!task.reason.isEmpty, "任务[\(index)] 理由为空: \(task.title)")
        }

        print("✅ parseThoughts 数据结构完整性: \(results.count) 个任务")
    }

    @Test("parseThoughts：传入已有任务不产生重复")
    func testParseThoughtsDeduplication() async throws {
        let apiKey = try TestFixtures.getAPIKey()
        let service = DeepSeekAIService(apiKey: apiKey, model: AppConstants.defaultModel)

        let existingTitles = ["写项目报告", "团队会议"]
        let results = try await service.parseThoughts(
            input: TestFixtures.sampleThoughtInput,
            existingTaskTitles: existingTitles
        )

        let resultTitles = results.map { $0.title }
        for existing in existingTitles {
            let exactMatch = resultTitles.filter { $0 == existing }
            #expect(exactMatch.isEmpty, "生成了与已有任务重复的任务: \(existing)")
        }

        print("✅ 去重验证: 已有 \(existingTitles.count) 个，新返回 \(results.count) 个均不重复")
    }

    @Test("parseThoughts：同一模型 3 次调用稳定性")
    func testParseThoughtsRepeatedStability() async throws {
        let apiKey = try TestFixtures.getAPIKey()
        let service = DeepSeekAIService(apiKey: apiKey, model: AppConstants.defaultModel)

        let rounds = 3
        var successCount = 0

        for round in 1...rounds {
            print("  🔄 parseThoughts 第 \(round)/\(rounds) 轮...")

            do {
                let results = try await service.parseThoughts(
                    input: TestFixtures.sampleThoughtInput,
                    existingTaskTitles: []
                )
                #expect(!results.isEmpty, "第 \(round) 轮返回了空结果")
                successCount += 1
                print("  ✅ 第 \(round) 轮: \(results.count) 个任务")
            } catch let error as NLPlanError {
                if case .aiAPIError(let statusCode, _) = error, statusCode == 429 {
                    print("  ⚠️ 第 \(round) 轮: 限流 (429)，等待 5 秒后重试")
                    try await Task.sleep(for: .seconds(5))
                    let retryResults = try await service.parseThoughts(
                        input: TestFixtures.sampleThoughtInput,
                        existingTaskTitles: []
                    )
                    #expect(!retryResults.isEmpty, "重试后仍返回空结果")
                    successCount += 1
                    continue
                }
                throw error
            }

            if round < rounds {
                try await Task.sleep(for: .seconds(3))
            }
        }

        #expect(successCount == rounds, "应有 \(rounds) 轮成功")
        print("✅ parseThoughts \(rounds) 轮调用均成功")
    }

    // MARK: - generateDailyGrade 稳定性

    @Test("generateDailyGrade：各模型接口可用性")
    func testGenerateDailyGradeAllModels() async throws {
        let apiKey = try TestFixtures.getAPIKey()

        for modelConfig in AppConstants.availableModels {
            print("📡 测试 generateDailyGrade: \(modelConfig.name) (\(modelConfig.id))")

            let service = DeepSeekAIService(apiKey: apiKey, model: modelConfig.id)

            do {
                let grade = try await service.generateDailyGrade(
                    summaryInput: TestFixtures.sampleSummaryInput
                )

                #expect(
                    Grade(rawValue: grade.grade.rawValue) != nil,
                    "\(modelConfig.name) 返回了无效评分等级: \(grade.grade.rawValue)"
                )
                #expect(!grade.summary.isEmpty, "\(modelConfig.name) 返回了空评价")
                #expect(!grade.suggestion.isEmpty, "\(modelConfig.name) 返回了空建议")
                #expect(!grade.gradingBasis.isEmpty, "\(modelConfig.name) 返回了空评分依据")
                #expect(grade.stats.totalTasks == TestFixtures.sampleSummaryInput.totalTasks,
                       "\(modelConfig.name) 总任务数不一致")
                #expect(grade.stats.completedTasks == TestFixtures.sampleSummaryInput.completedTasks,
                       "\(modelConfig.name) 完成任务数不一致")

                print("  ✅ \(modelConfig.name): 评分 \(grade.grade.rawValue)")
            } catch let error as NLPlanError {
                if case .aiAPIError(let statusCode, _) = error, statusCode == 429 {
                    print("  ⚠️ \(modelConfig.name): 限流 (429)，等待 5 秒后继续")
                    try await Task.sleep(for: .seconds(5))
                    continue
                }
                print("  ❌ \(modelConfig.name): 失败 - \(error.errorDescription ?? error.localizedDescription)")
                throw error
            }

            try await Task.sleep(for: .seconds(3))
        }
    }

    @Test("generateDailyGrade：返回数据结构完整性")
    func testGenerateDailyGradeResponseStructure() async throws {
        let apiKey = try TestFixtures.getAPIKey()
        let service = DeepSeekAIService(apiKey: apiKey, model: AppConstants.defaultModel)

        let grade = try await service.generateDailyGrade(
            summaryInput: TestFixtures.sampleSummaryInput
        )

        #expect(Grade(rawValue: grade.grade.rawValue) != nil)
        #expect(!grade.summary.isEmpty, "summary 为空")
        #expect(!grade.suggestion.isEmpty, "suggestion 为空")
        #expect(!grade.gradingBasis.isEmpty, "gradingBasis 为空")
        #expect(grade.stats.totalTasks >= 0)
        #expect(grade.stats.completedTasks >= 0)
        #expect(grade.stats.totalPlannedMinutes >= 0)
        #expect(grade.stats.totalActualMinutes >= 0)
        #expect(grade.stats.deviationRate >= 0)

        print("✅ generateDailyGrade 结构完整: 等级=\(grade.grade.rawValue)")
    }

    @Test("generateDailyGrade：同一模型 3 次调用稳定性")
    func testGenerateDailyGradeRepeatedStability() async throws {
        let apiKey = try TestFixtures.getAPIKey()
        let service = DeepSeekAIService(apiKey: apiKey, model: AppConstants.defaultModel)

        let rounds = 3
        var successCount = 0

        for round in 1...rounds {
            print("  🔄 generateDailyGrade 第 \(round)/\(rounds) 轮...")

            do {
                let grade = try await service.generateDailyGrade(
                    summaryInput: TestFixtures.sampleSummaryInput
                )
                #expect(Grade(rawValue: grade.grade.rawValue) != nil)
                #expect(!grade.summary.isEmpty)
                successCount += 1
                print("  ✅ 第 \(round) 轮: 评分 \(grade.grade.rawValue)")
            } catch let error as NLPlanError {
                if case .aiAPIError(let statusCode, _) = error, statusCode == 429 {
                    print("  ⚠️ 第 \(round) 轮: 限流 (429)，等待 5 秒后重试")
                    try await Task.sleep(for: .seconds(5))
                    let retryGrade = try await service.generateDailyGrade(
                        summaryInput: TestFixtures.sampleSummaryInput
                    )
                    #expect(Grade(rawValue: retryGrade.grade.rawValue) != nil)
                    successCount += 1
                    continue
                }
                throw error
            }

            if round < rounds {
                try await Task.sleep(for: .seconds(3))
            }
        }

        #expect(successCount == rounds, "应有 \(rounds) 轮成功")
        print("✅ generateDailyGrade \(rounds) 轮调用均成功")
    }

    // MARK: - appealGrade 稳定性

    @Test("appealGrade：默认模型接口可用性")
    func testAppealGradeStability() async throws {
        let apiKey = try TestFixtures.getAPIKey()
        let service = DeepSeekAIService(apiKey: apiKey, model: AppConstants.defaultModel)

        print("📡 测试 appealGrade: \(AppConstants.defaultModel)")

        let appealedGrade = try await service.appealGrade(
            originalGrade: TestFixtures.sampleOriginalGrade,
            originalInput: TestFixtures.sampleSummaryInput,
            userFeedback: TestFixtures.sampleAppealFeedback
        )

        #expect(Grade(rawValue: appealedGrade.grade.rawValue) != nil,
               "驳斥评分返回了无效等级: \(appealedGrade.grade.rawValue)")
        #expect(!appealedGrade.summary.isEmpty, "驳斥评分返回了空评价")
        #expect(!appealedGrade.suggestion.isEmpty, "驳斥评分返回了空建议")
        #expect(!appealedGrade.gradingBasis.isEmpty, "驳斥评分返回了空评分依据")
        #expect(appealedGrade.stats.totalTasks == TestFixtures.sampleSummaryInput.totalTasks)
        #expect(appealedGrade.stats.completedTasks == TestFixtures.sampleSummaryInput.completedTasks)
        #expect(appealedGrade.stats.extraCompleted == TestFixtures.sampleSummaryInput.extraCompleted)

        print("✅ appealGrade 验证通过: 驳斥后评分 \(appealedGrade.grade.rawValue)")
    }

    @Test("appealGrade：各模型接口可用性")
    func testAppealGradeAllModels() async throws {
        let apiKey = try TestFixtures.getAPIKey()

        for modelConfig in AppConstants.availableModels {
            print("📡 测试 appealGrade: \(modelConfig.name) (\(modelConfig.id))")

            let service = DeepSeekAIService(apiKey: apiKey, model: modelConfig.id)

            do {
                let grade = try await service.appealGrade(
                    originalGrade: TestFixtures.sampleOriginalGrade,
                    originalInput: TestFixtures.sampleSummaryInput,
                    userFeedback: TestFixtures.sampleAppealFeedback
                )

                #expect(Grade(rawValue: grade.grade.rawValue) != nil,
                       "\(modelConfig.name) 返回了无效评分等级")
                #expect(!grade.summary.isEmpty, "\(modelConfig.name) 返回了空评价")
                #expect(!grade.gradingBasis.isEmpty, "\(modelConfig.name) 返回了空评分依据")

                print("  ✅ \(modelConfig.name): 驳斥后评分 \(grade.grade.rawValue)")
            } catch let error as NLPlanError {
                if case .aiAPIError(let statusCode, _) = error, statusCode == 429 {
                    print("  ⚠️ \(modelConfig.name): 限流 (429)，等待 5 秒后继续")
                    try await Task.sleep(for: .seconds(5))
                    continue
                }
                print("  ❌ \(modelConfig.name): 失败 - \(error.errorDescription ?? error.localizedDescription)")
                throw error
            }

            try await Task.sleep(for: .seconds(3))
        }
    }

    // MARK: - 错误处理

    @Test("错误处理：无效 API Key 返回认证错误")
    func testInvalidAPIKey() async {
        let service = DeepSeekAIService(apiKey: "invalid-test-key-12345", model: AppConstants.defaultModel)

        do {
            _ = try await service.parseThoughts(
                input: TestFixtures.sampleThoughtInput,
                existingTaskTitles: []
            )
            #expect(Bool(false), "无效 API Key 应该抛出错误")
        } catch let error as NLPlanError {
            if case .aiAPIError(let statusCode, _) = error {
                #expect(statusCode == 401, "期望 401 状态码，实际: \(statusCode)")
                print("✅ 无效 API Key 正确返回 401")
            } else {
                print("⚠️ 非 HTTP 错误: \(error)")
            }
        } catch {
            print("⚠️ 网络错误: \(error)")
        }
    }
}
