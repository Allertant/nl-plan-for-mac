import Testing
import Foundation
@testable import NLPlan

// MARK: - Grade Tests

@Suite("Grade Tests")
struct GradeTests {

    @Test("S 等级不属于任何规则化评分")
    func testSGradeNotFromRules() {
        // S 需要额外完成想法池任务，纯规则无法得到 S
        let grade = Grade.fromCompletionRate(1.0)
        #expect(grade == .A) // 完成率100%给A
    }

    @Test("完成率 100% → A")
    func testCompletionRate100() {
        let grade = Grade.fromCompletionRate(1.0)
        #expect(grade == .A)
    }

    @Test("完成率 80%-99% → B")
    func testCompletionRate80() {
        let grade = Grade.fromCompletionRate(0.85)
        #expect(grade == .B)
    }

    @Test("完成率 50%-79% → C")
    func testCompletionRate50() {
        let grade = Grade.fromCompletionRate(0.6)
        #expect(grade == .C)
    }

    @Test("完成率 <50% → D")
    func testCompletionRate30() {
        let grade = Grade.fromCompletionRate(0.3)
        #expect(grade == .D)
    }

    @Test("完成率 0% → D")
    func testCompletionRate0() {
        let grade = Grade.fromCompletionRate(0.0)
        #expect(grade == .D)
    }
}

// MARK: - NLPlanError Tests

@Suite("NLPlanError Tests")
struct NLPlanErrorTests {

    @Test("emptyInput 有描述")
    func testEmptyInputDescription() {
        let error = NLPlanError.emptyInput
        #expect(error.errorDescription == "请输入内容后再提交")
    }

    @Test("apiKeyNotConfigured 有描述")
    func testAPIKeyNotConfiguredDescription() {
        let error = NLPlanError.apiKeyNotConfigured
        #expect(error.errorDescription == "请先配置 API Key")
    }

    @Test("appealLimitExceeded 有描述")
    func testAppealLimitExceededDescription() {
        let error = NLPlanError.appealLimitExceeded
        #expect(error.errorDescription == "今日申诉次数已达上限（3次）")
    }
}

// MARK: - TaskPool Tests

@Suite("TaskPool Tests")
struct TaskPoolTests {

    @Test("TaskPool rawValue 正确")
    func testRawValues() {
        #expect(TaskPool.ideaPool.rawValue == "idea_pool")
        #expect(TaskPool.mustDo.rawValue == "must_do")
    }

    @Test("TaskPool displayName 正确")
    func testDisplayNames() {
        #expect(TaskPool.ideaPool.displayName == "想法池")
        #expect(TaskPool.mustDo.displayName == "必做项")
    }
}

// MARK: - TaskStatus Tests

@Suite("TaskStatus Tests")
struct TaskStatusTests {

    @Test("TaskStatus 所有状态")
    func testAllStatuses() {
        #expect(TaskStatus.pending.rawValue == "pending")
        #expect(TaskStatus.running.rawValue == "running")
        #expect(TaskStatus.paused.rawValue == "paused")
        #expect(TaskStatus.done.rawValue == "done")
    }
}

// MARK: - TaskPriority Tests

@Suite("TaskPriority Tests")
struct TaskPriorityTests {

    @Test("TaskPriority rawValue 正确")
    func testRawValues() {
        #expect(TaskPriority.high.rawValue == "high")
        #expect(TaskPriority.medium.rawValue == "medium")
        #expect(TaskPriority.low.rawValue == "low")
    }
}
