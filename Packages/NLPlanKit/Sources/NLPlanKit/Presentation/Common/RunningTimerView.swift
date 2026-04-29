import SwiftUI

/// 运行中的计时器显示（每秒刷新）
struct RunningTimerView: View {
    let elapsedSeconds: Int
    var isPaused: Bool = false

    @State private var tick = 0

    var body: some View {
        Text(formatDuration(seconds: elapsedSeconds))
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(isPaused ? Color.secondary : Color.green)
            .onAppear { startTimer() }
            .onDisappear { timer?.invalidate() }
            .onChange(of: elapsedSeconds) { _, _ in
                // 外部值变化时触发重绘
                tick &+= 1
            }
    }

    @State private var timer: Timer?

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            tick &+= 1
        }
    }

    private func formatDuration(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }
}
