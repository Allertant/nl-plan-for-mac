import SwiftUI

struct HoverIconButton: View {
    let icon: String
    let iconSize: CGFloat
    let color: Color
    let padding: CGFloat
    let cornerRadius: CGFloat
    let action: () -> Void

    @State private var isHovered = false

    init(
        icon: String,
        iconSize: CGFloat = 12,
        color: Color = .secondary,
        padding: CGFloat = 4,
        cornerRadius: CGFloat = 4,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.iconSize = iconSize
        self.color = color
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: iconSize))
                .foregroundStyle(color)
                .padding(padding)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(isHovered ? Color.primary.opacity(0.08) : .clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
