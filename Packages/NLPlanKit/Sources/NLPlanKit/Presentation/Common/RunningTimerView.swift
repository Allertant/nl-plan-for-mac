import SwiftUI

/// 运行中的计时器显示
struct RunningTimerView: View {
    let taskId: UUID
    let timerEngine: TimerEngine

    @State private var displayText: String = "00:00:00"
    @State private var timer: Timer?

    var body: some View {
        Text(displayText)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.green)
            .onAppear {
                startTimer()
            }
            .onDisappear {
                timer?.invalidate()
            }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task {
                let seconds = await timerEngine.elapsedSeconds(for: taskId)
                let hours = seconds / 3600
                let minutes = (seconds % 3600) / 60
                let secs = seconds % 60
                await MainActor.run {
                    self.displayText = String(format: "%02d:%02d:%02d", hours, minutes, secs)
                }
            }
        }
    }
}
