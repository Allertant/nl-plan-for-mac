import SwiftUI

/// 运行中的计时器显示（本地每秒累加）
struct RunningTimerView: View {
    let initialSeconds: Int
    var isPaused: Bool = false

    @State private var addedSeconds: Int = 0
    @State private var timer: Timer?

    private var totalSeconds: Int {
        isPaused ? initialSeconds : initialSeconds + addedSeconds
    }

    var body: some View {
        Text(formatDuration(seconds: totalSeconds))
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(isPaused ? Color.secondary : Color.green)
            .onAppear {
                addedSeconds = 0
                guard !isPaused else { return }
                startTimer()
            }
            .onDisappear { timer?.invalidate(); timer = nil }
            .onChange(of: isPaused) { _, paused in
                if paused {
                    timer?.invalidate(); timer = nil
                } else {
                    addedSeconds = 0
                    startTimer()
                }
            }
            .onChange(of: initialSeconds) { _, _ in
                addedSeconds = 0
            }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            addedSeconds += 1
        }
    }

    private func formatDuration(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }
}
