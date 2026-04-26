import SwiftUI

/// 菜单栏标签视图
struct MenuBarLabelView: View {
    @Bindable var appState: AppState

    var body: some View {
        if !appState.isAPIKeyConfigured {
            HStack(spacing: 4) {
                Image(systemName: "sparkle")
                Text("请配置 API")
            }
            .font(.system(size: 12, weight: .medium))
        } else if appState.isTimerRunning {
            HStack(spacing: 4) {
                Image(systemName: "sparkle")
                Text("\(appState.timerDisplayText) \(truncateTitle(appState.currentTaskTitle))")
            }
            .font(.system(size: 12, weight: .medium, design: .monospaced))
        } else {
            Image(systemName: "sparkle")
        }
    }

    private func truncateTitle(_ title: String) -> String {
        if title.count > 10 {
            return String(title.prefix(10)) + "…"
        }
        return title
    }
}
