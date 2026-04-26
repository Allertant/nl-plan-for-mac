import SwiftUI
import AppKit

/// 强制隐藏外层面板滚动条，避免滚动条显隐导致布局抖动
struct ScrollViewScrollerHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let scrollView = nsView.enclosingScrollView else { return }
            scrollView.hasVerticalScroller = false
            scrollView.autohidesScrollers = true
            scrollView.scrollerStyle = .overlay
        }
    }
}

/// 读取 NSScrollView 的真实状态，判断是否超过一屏可滚动
struct ScrollViewStateObserver: NSViewRepresentable {
    @Binding var hasOverflow: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(hasOverflow: $hasOverflow)
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.attachIfNeeded(to: nsView)
        context.coordinator.updateState()
    }

    final class Coordinator {
        @Binding private var hasOverflow: Bool
        private weak var observedScrollView: NSScrollView?
        private var boundsObserver: NSObjectProtocol?

        init(hasOverflow: Binding<Bool>) {
            _hasOverflow = hasOverflow
        }

        deinit {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
        }

        func attachIfNeeded(to nsView: NSView) {
            guard let scrollView = nsView.enclosingScrollView else { return }
            guard observedScrollView !== scrollView else { return }

            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
                self.boundsObserver = nil
            }

            observedScrollView = scrollView
            scrollView.contentView.postsBoundsChangedNotifications = true
            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                self?.updateState()
            }

            DispatchQueue.main.async { [weak self] in
                self?.updateState()
            }
        }

        func updateState() {
            guard let scrollView = observedScrollView else { return }
            let contentHeight = scrollView.documentView?.frame.height ?? 0
            let viewportHeight = scrollView.contentView.bounds.height
            hasOverflow = contentHeight > viewportHeight + 1
        }
    }
}
