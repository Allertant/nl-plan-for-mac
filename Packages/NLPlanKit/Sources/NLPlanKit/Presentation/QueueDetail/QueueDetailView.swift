import SwiftUI

/// 队列项详情页（全屏确认）
struct QueueDetailView: View {
    @Environment(AppState.self) private var appState
    @Bindable var viewModel: InputViewModel
    let queueItem: ParseQueueItemEntity

    @State private var editedRawText: String = ""
    @State private var didInitRawText = false

    private var isLocked: Bool {
        viewModel.isItemChatProcessing(id: queueItem.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部栏
            HStack(spacing: 8) {
                BackButton { appState.currentPage = .main }
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
                Text("想法审核")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            // 内容区
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    // 用户原始输入（直接可编辑）
                    VStack(alignment: .leading, spacing: 4) {
                        Label("我的输入", systemImage: "text.bubble")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)

                        TextEditor(text: $editedRawText)
                            .font(.system(size: 12))
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 40, maxHeight: 120)
                            .onChange(of: editedRawText) { _, newValue in
                                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !trimmed.isEmpty {
                                    viewModel.updateRawText(queueItemID: queueItem.id, newText: newValue)
                                }
                            }
                    }
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
                    .onAppear {
                        if !didInitRawText {
                            editedRawText = queueItem.rawText
                            didInitRawText = true
                        }
                    }

                    Divider()

                    // 解析结果列表
                    if let parsedTasks = queueItem.parsedTasks {
                        Text("AI 解析结果（\(parsedTasks.count) 个任务）")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)

                        ForEach(parsedTasks, id: \.id) { task in
                            ParsedTaskRow(
                                task: task,
                                isLocked: isLocked,
                                onEdit: { title, category, minutes, note in
                                    viewModel.updateParsedTask(
                                        queueItemID: queueItem.id,
                                        taskID: task.id,
                                        title: title,
                                        category: category,
                                        estimatedMinutes: minutes,
                                        note: note
                                    )
                                },
                                onDelete: {
                                    let cleared = viewModel.removeParsedTask(
                                        queueItemID: queueItem.id,
                                        taskID: task.id
                                    )
                                    if cleared { appState.currentPage = .main }
                                },
                                onApprove: {
                                    Task {
                                        let cleared = await viewModel.approveSingleTask(
                                            queueItemID: queueItem.id,
                                            taskID: task.id
                                        )
                                        if cleared { appState.currentPage = .main }
                                    }
                                },
                                onToggleProject: {
                                    viewModel.toggleProjectState(
                                        queueItemID: queueItem.id,
                                        taskID: task.id
                                    )
                                }
                            )
                        }
                    }

                    // AI 调整成功提示
                    if let success = viewModel.successMessage {
                        Text(success)
                            .font(.system(size: 11))
                            .foregroundStyle(.green)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.opacity)
                            .onAppear {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                    viewModel.successMessage = nil
                                }
                            }
                    }

                    // 追问处理中状态
                    if isLocked {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("AI 正在处理你的调整...")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.accentColor.opacity(0.08))
                        .cornerRadius(6)
                        .transition(.opacity)
                    }

                    // AI 对话输入区
                    HStack(alignment: .top) {
                        TextField("告诉 AI 你想怎么调整...", text: $viewModel.chatInput, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(1...3)
                            .font(.system(size: 12))
                            .onSubmit {
                                Task { await viewModel.sendModification(queueItemID: queueItem.id) }
                            }

                        Button {
                            Task { await viewModel.sendModification(queueItemID: queueItem.id) }
                        } label: {
                            if isLocked {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 12))
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(isLocked || viewModel.chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)

                    // 操作按钮
                    HStack {
                        Button {
                            viewModel.cancelQueueItem(id: queueItem.id)
                            appState.currentPage = .main
                        } label: {
                            Text("取消")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.borderless)
                        .disabled(isLocked)

                        Spacer()

                        Button {
                            Task {
                                await viewModel.confirmQueueItem(id: queueItem.id)
                                appState.currentPage = .main
                            }
                        } label: {
                            Text("全部确认添加")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.borderless)
                        .disabled(isLocked)
                    }
                    .padding(.top, 2)
                }
                .padding(12)
            }
        }
        .frame(width: 360, height: 520)
    }
}
