import SwiftUI

struct HoverTextButton: View {
    let title: String
    let color: Color
    let isEmphasized: Bool
    let action: () -> Void

    @State private var isHovered = false

    init(
        _ title: String,
        color: Color = .secondary,
        isEmphasized: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.color = color
        self.isEmphasized = isEmphasized
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: isEmphasized ? .medium : .regular))
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? Color.primary.opacity(0.08) : .clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
