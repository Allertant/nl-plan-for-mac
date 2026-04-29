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
        } else {
            Image(systemName: "sparkle")
        }
    }
}
