import SwiftUI

extension String {
    /// 标签颜色调色板（10种柔和颜色）
    private static var tagColorPalette: [Color] {
        [
            Color.blue.opacity(0.8),
            Color.green.opacity(0.75),
            Color.orange.opacity(0.8),
            Color.purple.opacity(0.75),
            Color.pink.opacity(0.8),
            Color.cyan.opacity(0.8),
            Color.yellow.opacity(0.85),
            Color.indigo.opacity(0.75),
            Color.mint.opacity(0.8),
            Color.red.opacity(0.75)
        ]
    }

    /// 根据标签名称获取固定颜色
    var tagColor: Color {
        let hash = unicodeScalars.reduce(0) { partialResult, scalar in
            (partialResult * 31 + Int(scalar.value)) % 10_000
        }
        let index = hash % Self.tagColorPalette.count
        return Self.tagColorPalette[index]
    }
}
