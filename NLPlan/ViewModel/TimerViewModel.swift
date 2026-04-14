import Foundation
import SwiftData

/// 计时器显示 ViewModel
@Observable
final class TimerViewModel {

    var displayText: String = ""
    var taskTitle: String = ""

    private let timerEngine: TimerEngine
    private var timer: Timer?

    init(timerEngine: TimerEngine) {
        self.timerEngine = timerEngine
        startTicker()
    }

    deinit {
        timer?.invalidate()
    }

    private func startTicker() {
        timer = Timer.scheduledTimer(withTimeInterval: AppConstants.timerRefreshInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { [weak self] in
                guard let self else { return }
                await self.tick()
            }
        }
    }

    private func tick() async {
        let activeIds = await timerEngine.activeTasks()
        if let firstId = activeIds.first {
            self.displayText = await timerEngine.timerDisplay(for: firstId)
        } else {
            self.displayText = ""
            self.taskTitle = ""
        }
    }
}
