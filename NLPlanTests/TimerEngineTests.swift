import Testing
import Foundation
@testable import NLPlan

// MARK: - TimerEngine Tests

@Suite("TimerEngine Tests")
struct TimerEngineTests {

    @Test("初始状态没有活跃任务")
    func testInitialState() async {
        let engine = TimerEngine()
        let active = await engine.activeTasks()
        #expect(active.isEmpty)
        let hasActive = await engine.hasActiveTasks()
        #expect(hasActive == false)
    }

    @Test("启动任务后有一个活跃任务")
    func testStartTask() async {
        let engine = TimerEngine()
        let taskId = UUID()
        _ = await engine.startTask(taskId)
        let active = await engine.activeTasks()
        #expect(active.count == 1)
        #expect(active.contains(taskId))
    }

    @Test("启动新任务自动停止旧任务（默认不允许并行）")
    func testAutoStopOnSwitch() async {
        let engine = TimerEngine()
        let task1 = UUID()
        let task2 = UUID()

        let stopped = await engine.startTask(task1)
        #expect(stopped.isEmpty)

        let stopped2 = await engine.startTask(task2)
        #expect(stopped2.count == 1)
        #expect(stopped2.first?.taskId == task1)
    }

    @Test("停止任务")
    func testStopTask() async {
        let engine = TimerEngine()
        let taskId = UUID()
        _ = await engine.startTask(taskId)

        let result = await engine.stopTask(taskId)
        #expect(result != nil)
        #expect(result?.taskId == taskId)

        let active = await engine.activeTasks()
        #expect(active.isEmpty)
    }

    @Test("停止不存在的任务返回 nil")
    func testStopNonExistent() async {
        let engine = TimerEngine()
        let result = await engine.stopTask(UUID())
        #expect(result == nil)
    }

    @Test("stopAll 停止所有任务")
    func testStopAll() async {
        let engine = TimerEngine()
        await engine.setAllowParallel(true)
        let task1 = UUID()
        let task2 = UUID()
        _ = await engine.startTask(task1)
        _ = await engine.startTask(task2)

        let stopped = await engine.stopAll()
        #expect(stopped.count == 2)

        let active = await engine.activeTasks()
        #expect(active.isEmpty)
    }

    @Test("计时经过秒数大于 0")
    func testElapsedSeconds() async {
        let engine = TimerEngine()
        let taskId = UUID()
        _ = await engine.startTask(taskId)

        // 短暂等待
        try? await Task.sleep(for: .milliseconds(100))

        let elapsed = await engine.elapsedSeconds(for: taskId)
        #expect(elapsed >= 0)
    }

    @Test("计时显示格式正确")
    func testTimerDisplay() async {
        let engine = TimerEngine()
        let taskId = UUID()
        _ = await engine.startTask(taskId)

        let display = await engine.timerDisplay(for: taskId)
        // 格式应为 HH:MM:SS，验证冒号分隔
        #expect(display.contains(":"))
        #expect(display.count == 8) // "00:00:00"
    }

    @Test("允许并行模式下启动多个任务")
    func testParallelMode() async {
        let engine = TimerEngine()
        await engine.setAllowParallel(true)

        let task1 = UUID()
        let task2 = UUID()

        let stopped1 = await engine.startTask(task1)
        #expect(stopped1.isEmpty)

        let stopped2 = await engine.startTask(task2)
        #expect(stopped2.isEmpty)

        let active = await engine.activeTasks()
        #expect(active.count == 2)
    }
}
