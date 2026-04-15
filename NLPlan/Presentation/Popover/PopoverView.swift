import SwiftUI
import AppKit

/// 主面板容器
struct PopoverView: View {
    @Environment(AppState.self) private var appState

    @Bindable var inputViewModel: InputViewModel
    @Bindable var ideaPoolViewModel: IdeaPoolViewModel
    @Bindable var mustDoViewModel: MustDoViewModel

    let timerEngine: TimerEngine

    var body: some View {
        VStack(spacing: 0) {
            if !appState.isAPIKeyConfigured {
                APIKeyNotConfiguredBanner()
            }

            ScrollView {
                VStack(spacing: 12) {
                    // 输入区
                    InputSection(viewModel: inputViewModel)

                    // 想法池
                    IdeaPoolSection(viewModel: ideaPoolViewModel)

                    // 必做项
                    MustDoSection(viewModel: mustDoViewModel, timerEngine: timerEngine)
                }
                .padding(12)
                .background(ScrollViewScrollerHider())
            }
            .scrollIndicators(.hidden)

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
        .onAppear {
            Task {
                await ideaPoolViewModel.refresh()
                await mustDoViewModel.refresh()
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
