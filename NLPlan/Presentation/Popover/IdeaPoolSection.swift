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
                            IdeaPoolTaskRow(task: task) {
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
    let onPromote: () -> Void
    let onDelete: () -> Void

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
                    Text("💡 \(reason)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
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
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(6)
    }
}
