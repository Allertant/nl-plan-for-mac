import SwiftUI

/// 想法池区域
struct IdeaPoolSection: View {
    @Bindable var viewModel: IdeaPoolViewModel

    var body: some View {
        VStack(spacing: 0) {
            // 折叠头部
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.yellow)
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
                    Image(systemName: viewModel.isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if viewModel.isExpanded {
                Divider()

                if viewModel.tasks.isEmpty {
                    Text("暂无想法")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 16)
                } else {
                    LazyVStack(spacing: 4) {
                        ForEach(viewModel.tasks, id: \.id) { task in
                            IdeaPoolTaskRow(task: task, isNew: viewModel.newlyAddedTaskIds.contains(task.id)) {
                                Task { await viewModel.promoteToMustDo(taskId: task.id) }
                            } onDelete: {
                                Task { await viewModel.deleteTask(taskId: task.id) }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        .cornerRadius(8)
    }
}

/// 想法池任务卡片
struct IdeaPoolTaskRow: View {
    let task: TaskEntity
    var isNew: Bool = false
    let onPromote: () -> Void
    let onDelete: () -> Void

    @State private var flashCount = 0

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(task.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(2)

                    if task.aiRecommended {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                    }

                    if task.attempted {
                        Text("已尝试")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.15))
                            .cornerRadius(3)
                    }
                }

                HStack(spacing: 8) {
                    Label(task.category, systemImage: "tag")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    Label("\(task.estimatedMinutes)分钟", systemImage: "clock")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    Text(task.createdDate.dateString)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                if task.aiRecommended, let reason = task.recommendationReason {
                    TooltipText(text: "💡 \(reason)", tooltip: reason)
                }
            }

            Spacer()

            VStack(spacing: 4) {
                Button {
                    onPromote()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                .help("加入必做项")

                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(.red.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("删除")
            }
        }
        .padding(8)
        .background(flashCount % 2 == 1 ? Color.accentColor.opacity(0.15) : Color(nsColor: .textBackgroundColor))
        .cornerRadius(6)
        .onAppear {
            if isNew {
                // 闪烁两次
                withAnimation(.easeInOut(duration: 0.3)) {
                    flashCount = 1
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        flashCount = 0
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        flashCount = 1
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        flashCount = 0
                    }
                }
            }
        }
    }
}

// MARK: - Tooltip Text

/// 带悬停提示的文本组件（替代 .help()，在 MenuBarExtra 窗口中生效）
struct TooltipText: View {
    let text: String
    let tooltip: String

    @State private var isHovered = false

    var body: some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .onHover { hovering in
                isHovered = hovering
            }
            .popover(isPresented: $isHovered, arrowEdge: .bottom) {
                Text(tooltip)
                    .font(.system(size: 12))
                    .padding(10)
                    .frame(width: 280, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
    }
}
