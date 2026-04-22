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

                    if !viewModel.tasks.isEmpty {
                        Text("\(viewModel.tasks.count)")
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
                ScrollView {
                    VStack(spacing: 0) {
                        Color.clear
                            .frame(height: 0)
                            .id("scroll-top-anchor")

                        IdeaPoolSection(viewModel: viewModel)
                    }
                    .padding(12)
                }
                .scrollIndicators(.never)
            }
            .frame(width: 360, height: 520)
            .overlay(alignment: .bottomTrailing) {
                if viewModel.tasks.count >= 5 {
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
                    .padding(.bottom, 14)
                }
            }
        }
    }
}
