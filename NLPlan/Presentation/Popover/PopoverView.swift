import SwiftUI
import AppKit

/// 主面板容器
struct PopoverView: View {
    @Environment(AppState.self) private var appState

    @Bindable var inputViewModel: InputViewModel
    @Bindable var ideaPoolViewModel: IdeaPoolViewModel
    @Bindable var mustDoViewModel: MustDoViewModel

    let timerEngine: TimerEngine

    @State private var hasScrollOverflow: Bool = false

    private var showBackToTopButton: Bool {
        ideaPoolViewModel.isExpanded &&
        (hasScrollOverflow || ideaPoolViewModel.tasks.count >= 5)
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                if !appState.isAPIKeyConfigured {
                    APIKeyNotConfiguredBanner()
                }

                ScrollView {
                    VStack(spacing: 12) {
                        Color.clear
                            .frame(height: 0)
                            .id("scroll-top-anchor")

                        // 输入区
                        InputSection(viewModel: inputViewModel)

                        // 解析队列
                        ParseQueueSection(viewModel: inputViewModel) { queueItemID in
                            appState.currentPage = .queueDetail(queueItemID)
                        }

                        // 想法池
                        IdeaPoolSection(viewModel: ideaPoolViewModel)

                        // 必做项
                        MustDoSection(viewModel: mustDoViewModel, timerEngine: timerEngine)
                    }
                    .padding(12)
                    .background(ScrollViewScrollerHider())
                }
                .scrollIndicators(.hidden)
                .background(
                    ScrollViewStateObserver(hasOverflow: $hasScrollOverflow)
                )

                Divider()

                // 底部操作栏
                HStack(spacing: 16) {
                    Spacer()

                    Button {
                        appState.currentPage = .summary
                    } label: {
                        Label("今日总结", systemImage: "chart.bar")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)

                    Button {
                        appState.currentPage = .history
                    } label: {
                        Label("历史", systemImage: "calendar")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)

                    Button {
                        appState.currentPage = .settings
                    } label: {
                        Label("设置", systemImage: "gear")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .frame(width: 360, height: 520)
            .overlay(alignment: .bottomTrailing) {
                if showBackToTopButton {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo("scroll-top-anchor", anchor: .top)
                        }
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.borderless)
                    .contentShape(Circle())
                    .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))
                    .clipShape(Circle())
                    .overlay(
                        Circle().stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.18), radius: 5, x: 0, y: 2)
                    .padding(.trailing, 14)
                    .padding(.bottom, 78)
                    .zIndex(10)
                }
            }
            .onAppear {
                Task {
                    await ideaPoolViewModel.refresh()
                    await mustDoViewModel.refresh()
                }
            }
        }
    }
}

/// 强制隐藏外层面板滚动条，避免滚动条显隐导致布局抖动
private struct ScrollViewScrollerHider: NSViewRepresentable {
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
private struct ScrollViewStateObserver: NSViewRepresentable {
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

/// API Key 未配置横幅
struct APIKeyNotConfiguredBanner: View {
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("请先在设置中配置 API Key")
                .font(.system(size: 12))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
    }
}
