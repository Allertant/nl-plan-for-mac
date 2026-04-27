import AppKit
import SwiftUI

// MARK: - Search Tag Views

struct SearchTagToken: View {
    let text: String; var isHighlighted: Bool = false; let onRemove: () -> Void
    var body: some View {
        HStack(spacing: 4) {
            TagChip(text: text)
            if !isHighlighted { Button(action: onRemove) { Image(systemName: "xmark.circle.fill").font(.system(size: 10)).foregroundStyle(.secondary) }.buttonStyle(.plain) }
        }.padding(.trailing, 2).overlay { if isHighlighted { RoundedRectangle(cornerRadius: 999).stroke(Color.accentColor.opacity(0.35), lineWidth: 1) } }
    }
}

struct DraftSearchTagToken: View {
    let text: String
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "tag.fill").font(.system(size: 7, weight: .semibold))
            Text(text.isEmpty ? "输入标签..." : text).font(.system(size: 9))
        }.padding(.horizontal, 6).padding(.vertical, 3).background(Color.accentColor.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 999).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3])).foregroundStyle(Color.accentColor.opacity(0.35)))
        .clipShape(Capsule()).foregroundStyle(Color.accentColor)
    }
}

enum SearchTagKeyCommand { case left, right, up, down, delete, blockTextInput }

struct SearchTagKeyMonitor: NSViewRepresentable {
    var isEnabled: Bool; let onCommand: (SearchTagKeyCommand) -> Bool
    func makeCoordinator() -> Coordinator { Coordinator(isEnabled: isEnabled, onCommand: onCommand) }
    func makeNSView(context: Context) -> NSView { let view = NSView(frame: .zero); context.coordinator.installMonitor(); return view }
    func updateNSView(_ nsView: NSView, context: Context) { context.coordinator.isEnabled = isEnabled; context.coordinator.onCommand = onCommand }
    static func dismantleNSView(_ nsview: NSView, coordinator: Coordinator) { coordinator.removeMonitor() }
    final class Coordinator {
        var isEnabled: Bool; var onCommand: (SearchTagKeyCommand) -> Bool; private var monitor: Any?
        init(isEnabled: Bool, onCommand: @escaping (SearchTagKeyCommand) -> Bool) { self.isEnabled = isEnabled; self.onCommand = onCommand }
        deinit { removeMonitor() }
        func installMonitor() { guard monitor == nil else { return }; monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in guard let self, self.isEnabled, let command = event.searchTagKeyCommand else { return event }; return self.onCommand(command) ? nil : event } }
        func removeMonitor() { if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil } }
    }
}

extension NSEvent {
    var searchTagKeyCommand: SearchTagKeyCommand? {
        let passthroughModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        guard modifierFlags.intersection(passthroughModifiers).isEmpty else { return nil }
        switch keyCode {
        case 51, 117: return .delete; case 123: return .left; case 124: return .right; case 125: return .down; case 126: return .up
        default: return charactersIgnoringModifiers?.isEmpty == false ? .blockTextInput : nil
        }
    }
}

// MARK: - Refreshing Icon

struct RefreshingIcon: View {
    let systemName: String; let isAnimating: Bool
    var body: some View {
        if isAnimating { TimelineView(.animation) { context in Image(systemName: systemName).rotationEffect(.degrees(angle(at: context.date))) } }
        else { Image(systemName: systemName) }
    }
    private func angle(at date: Date) -> Double { (date.timeIntervalSinceReferenceDate.remainder(dividingBy: 0.9) / 0.9) * 360 }
}
