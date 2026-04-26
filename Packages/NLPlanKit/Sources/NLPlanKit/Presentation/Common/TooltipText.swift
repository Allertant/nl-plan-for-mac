import SwiftUI

/// 带悬停提示的文本组件（替代 .help()，在 MenuBarExtra 窗口中生效）
struct TooltipText: View {
    let text: String
    let tooltip: String
    var showDelaySeconds: Double = 0.35

    @State private var isHovered = false
    @State private var showTooltip = false
    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .onHover { hovering in
                isHovered = hovering
                hoverTask?.cancel()
                hoverTask = nil

                if hovering {
                    hoverTask = Task {
                        try? await Task.sleep(for: .seconds(showDelaySeconds))
                        guard !Task.isCancelled, isHovered else { return }
                        showTooltip = true
                    }
                } else {
                    showTooltip = false
                }
            }
            .onDisappear {
                hoverTask?.cancel()
                hoverTask = nil
            }
            .popover(isPresented: $showTooltip, arrowEdge: .bottom) {
                Text(tooltip)
                    .font(.system(size: 12))
                    .padding(10)
                    .frame(width: 280, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
    }
}
