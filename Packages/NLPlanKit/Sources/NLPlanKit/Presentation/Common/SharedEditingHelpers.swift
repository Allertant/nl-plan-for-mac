import AppKit
import SwiftUI

/// 分类选择弹出菜单（供 IdeaPoolTaskRow 和 ParsedTaskRow 复用）
struct CategoryPickerMenu: View {
    let currentCategory: String
    let onSelect: (String) -> Void

    private var tags: [String] {
        UserDefaults.standard.stringArray(forKey: AppConstants.tagsKey) ?? AppConstants.defaultTags
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(tags, id: \.self) { tag in
                Button {
                    onSelect(tag)
                } label: {
                    HStack(spacing: 6) {
                        if tag == currentCategory {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                        } else {
                            Color.clear.frame(width: 10, height: 10)
                        }
                        TagChip(text: tag)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .frame(width: 180)
    }
}

/// 将光标移到当前焦点 TextField 的末尾
enum CursorHelper {
    static func moveInsertionPointToEnd(retryCount: Int = 3) {
        DispatchQueue.main.async {
            guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else {
                if retryCount > 0 { moveInsertionPointToEnd(retryCount: retryCount - 1) }
                return
            }
            let endLocation = textView.string.count
            textView.setSelectedRange(NSRange(location: endLocation, length: 0))
        }
    }
}
