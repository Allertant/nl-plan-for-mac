import SwiftUI

/// 带悬停提示的文本组件（替代 .help()，在 MenuBarExtra 窗口中生效）
struct TooltipText: View {
    let text: String
    let tooltip: String

    @State private var isHovered = false

    var body: some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .onHover { hovering in
                isHovered = hovering
            }
            .popover(isPresented: $isHovered, arrowEdge: .bottom) {
                Text(tooltip)
                    .font(.system(size: 12))
                    .padding(10)
                    .frame(width: 280, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
    }
}
