import SwiftUI
import AppKit

/// 强制隐藏外层面板滚动条，避免滚动条显隐导致布局抖动
struct ScrollViewScrollerHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ScrollerHiderView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ScrollerHiderView)?.configureScrollView()
    }
}

private final class ScrollerHiderView: NSView {
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        configureScrollView()
    }

    func configureScrollView() {
        guard let scrollView = enclosingScrollView else { return }
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
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

/// 记录并按需恢复 NSScrollView 的真实纵向偏移，避免 anchor 滚动带来的轻微错位
struct ScrollViewOffsetTracker: NSViewRepresentable {
    @Binding var offsetY: CGFloat
    @Binding var shouldRestore: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(offsetY: $offsetY, shouldRestore: $shouldRestore)
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.attachIfNeeded(to: nsView)
        context.coordinator.restoreIfNeeded()
    }

    final class Coordinator {
        @Binding private var offsetY: CGFloat
        @Binding private var shouldRestore: Bool
        private weak var observedScrollView: NSScrollView?
        private var boundsObserver: NSObjectProtocol?

        init(offsetY: Binding<CGFloat>, shouldRestore: Binding<Bool>) {
            _offsetY = offsetY
            _shouldRestore = shouldRestore
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
            ) { [weak self, weak scrollView] _ in
                guard let self, let scrollView else { return }
                self.offsetY = scrollView.contentView.bounds.origin.y
            }
        }

        func restoreIfNeeded() {
            guard shouldRestore, let scrollView = observedScrollView else { return }
            let documentHeight = scrollView.documentView?.bounds.height ?? 0
            let viewportHeight = scrollView.contentView.bounds.height
            let maxOffset = max(0, documentHeight - viewportHeight)
            let targetY = min(max(offsetY, 0), maxOffset)
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            DispatchQueue.main.async { [weak self] in
                self?.shouldRestore = false
            }
        }
    }
}
