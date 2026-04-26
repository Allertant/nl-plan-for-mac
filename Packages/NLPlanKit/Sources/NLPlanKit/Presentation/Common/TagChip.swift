import SwiftUI

/// 统一的标签胶囊样式
struct TagChip: View {
    let text: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "tag.fill")
                .font(.system(size: 7, weight: .semibold))
            Text(text)
                .font(.system(size: 9))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(text.tagColor.opacity(0.14))
        .clipShape(Capsule())
        .foregroundStyle(text.tagColor)
    }
}
