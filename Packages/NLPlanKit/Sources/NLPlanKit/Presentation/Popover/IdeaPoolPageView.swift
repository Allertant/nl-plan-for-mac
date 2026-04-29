import SwiftUI

/// 想法池独立页面
struct IdeaPoolPageView: View {
    @Bindable var viewModel: IdeaPoolViewModel
    let onBack: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                // 顶部导航栏
                HStack {
                    BackButton(action: onBack)

                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.yellow)
                        .font(.system(size: 12))

                    Text("想法池")
                        .font(.system(size: 13, weight: .semibold))

                    if !viewModel.ideas.isEmpty {
                        Text("\(viewModel.ideas.count)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(nsColor: .windowBackgroundColor))

                Divider()

                // 内容区
                if viewModel.pendingDeleteIdeaId != nil {
                    ConfirmActionPage(
                        icon: "trash",
                        iconTint: .red,
                        title: viewModel.pendingDeleteIdeaTitle ?? "",
                        message: "确认删除该想法？",
                        confirmLabel: "确认删除",
                        onCancel: { viewModel.cancelDelete() },
                        onConfirm: { Task { await viewModel.executeDelete() } }
                    )
                } else {
                ScrollView {
                    VStack(spacing: 0) {
                        Color.clear
                            .frame(height: 0)
                            .id("scroll-top-anchor")

                        IdeaPoolSection(viewModel: viewModel)
                            .padding(12)
                            .padding(.bottom, 40)
                    }
                    .background(
                        Color(nsColor: .windowBackgroundColor)
                            .contentShape(Rectangle())
                            .onTapGesture { NSApp.keyWindow?.makeFirstResponder(nil) }
                    )
                }
                .scrollIndicators(.automatic)
                }
            }
            .frame(width: 360, height: 520)
            .overlay(alignment: .bottomTrailing) {
                if viewModel.ideas.count >= 5 {
                    ScrollToTopButton {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo("scroll-top-anchor", anchor: .top)
                        }
                    }
                    .padding(.trailing, 14)
                    .padding(.bottom, 20)
                }
            }
        }
    }
}

private struct ScrollToTopButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.up")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.borderless)
        .contentShape(Circle())
        .background(
            Circle()
                .fill(isHovered ? Color.white : Color(nsColor: .windowBackgroundColor).opacity(0.95))
        )
        .overlay(
            Circle().stroke(Color.secondary.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 5, x: 0, y: 2)
        .onHover { isHovered = $0 }
    }
}
