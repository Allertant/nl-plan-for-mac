import SwiftUI

/// AI 清理详情页
struct CleanupDetailView: View {
    @Bindable var viewModel: IdeaPoolViewModel
    let onBack: () -> Void

    private var taskLookup: [UUID: IdeaEntity] {
        Dictionary(uniqueKeysWithValues: viewModel.ideas.map { ($0.id, $0) })
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部导航栏
            HStack {
                BackButton {
                    Task { await viewModel.commitCleanupDeletes() }
                    onBack()
                }

                Text("AI 清理建议")
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                if case .loaded(let result) = viewModel.cleanupState {
                    let remaining = result.items.count
                    if remaining > 0 {
                        Text("剩余 \(remaining) 项")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // 内容区
            if viewModel.pendingDeleteCleanupId != nil {
                ConfirmActionPage(
                    icon: "trash",
                    iconTint: .red,
                    title: viewModel.pendingDeleteCleanupTitle ?? "",
                    message: "确认删除该想法？",
                    confirmLabel: "确认删除",
                    onCancel: { viewModel.cancelDeleteCleanup() },
                    onConfirm: { Task { await viewModel.executeDeleteCleanup() } }
                )
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        switch viewModel.cleanupState {
                        case .loading:
                            VStack(spacing: 12) {
                                ProgressView()
                                    .controlSize(.regular)
                                Text("AI 正在分析想法池...")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)

                        case .loaded(let result):
                            if result.items.isEmpty {
                                VStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 32))
                                        .foregroundStyle(.green)
                                    Text("想法池很整洁，无需清理")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 80)
                            } else {
                                if !result.overallReason.isEmpty {
                                    Text(result.overallReason)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 4)
                                }

                                ForEach(result.items) { item in
                                    if let task = taskLookup[item.taskId] {
                                        CleanupDetailRow(
                                            task: task,
                                            reason: item.reason,
                                            onDelete: { viewModel.requestDeleteCleanup(taskId: item.taskId) },
                                            onSkip: { viewModel.skipCleanupItem(taskId: item.taskId) }
                                        )
                                    }
                                }
                            }

                        case .error(let message):
                            VStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 24))
                                    .foregroundStyle(.red)
                                Text(message)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.red)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)

                        case .idle:
                            EmptyView()
                        }
                    }
                    .padding(16)
                }
                .scrollIndicators(.automatic)

                // 底部操作栏
                if case .loaded = viewModel.cleanupState {
                    Divider()
                    HStack {
                        Button {
                            Task { await viewModel.commitCleanupDeletes() }
                            onBack()
                        } label: {
                            Text("全部跳过")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)

                        Spacer()

                        Button {
                            viewModel.undoLastCleanup()
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(viewModel.canUndoCleanup ? Color.primary : Color.gray.opacity(0.3))
                        .disabled(!viewModel.canUndoCleanup)
                        .help("撤销")

                        Button {
                            viewModel.markAllCleanupItems()
                        } label: {
                            Text("全部清除")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
        }
        .frame(width: 360, height: 520)
    }
}

// MARK: - 清理详情行

private struct CleanupDetailRow: View {
    let task: IdeaEntity
    let reason: String
    let onDelete: () -> Void
    let onSkip: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Label(task.category, systemImage: "tag")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    if let estimatedMinutes = task.estimatedMinutes {
                        Label(estimatedMinutes.hourMinuteString, systemImage: "clock")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }

                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                    Text(reason)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(spacing: 4) {
                Button(action: onSkip) {
                    Text("跳过")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button(action: onDelete) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(6)
    }
}
