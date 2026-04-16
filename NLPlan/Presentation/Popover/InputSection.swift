import SwiftUI

/// 输入区视图
struct InputSection: View {
    @Bindable var viewModel: InputViewModel

    var body: some View {
        VStack(spacing: 8) {
            // 输入区 / 已提交文本
            HStack(alignment: .top) {
                if viewModel.isProcessing {
                    Text(viewModel.submittedText)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.primary.opacity(0.5))
                        .lineLimit(2...5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if viewModel.pendingParsedTasks == nil {
                    TextField("输入你的想法和计划...", text: $viewModel.inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(2...5)
                        .font(.system(size: 13))
                        .onSubmit {
                            Task { await viewModel.submit() }
                        }
                }

                if viewModel.pendingParsedTasks == nil {
                    Button {
                        Task { await viewModel.submit() }
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.borderless)
                    .disabled(viewModel.isProcessing || viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(10)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(8)

            if viewModel.isProcessing {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("AI 正在解析...")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            }

            // AI 解析结果确认区
            if let parsedTasks = viewModel.pendingParsedTasks {
                ParsedTaskConfirmation(
                    originalInput: viewModel.submittedText,
                    parsedTasks: parsedTasks,
                    onConfirm: {
                        Task { await viewModel.confirm() }
                    },
                    onCancel: {
                        viewModel.cancelConfirmation()
                    }
                )
            }

            if let success = viewModel.successMessage {
                Text(success)
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .transition(.opacity)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            viewModel.successMessage = nil
                        }
                    }
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
        }
    }
}

/// AI 解析结果确认卡片
private struct ParsedTaskConfirmation: View {
    let originalInput: String
    let parsedTasks: [ParsedTask]
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 用户原始输入
            VStack(alignment: .leading, spacing: 4) {
                Label("你的输入", systemImage: "text.bubble")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(originalInput)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .lineLimit(3...8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
            .cornerRadius(6)

            Divider().padding(.horizontal, -2)

            // 解析结果列表
            VStack(alignment: .leading, spacing: 4) {
                Text("AI 解析结果（\(parsedTasks.count) 个任务）")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                ForEach(parsedTasks) { task in
                    ParsedTaskRow(task: task)
                }
            }

            // 操作按钮
            HStack {
                Button {
                    onCancel()
                } label: {
                    Text("取消")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    onConfirm()
                } label: {
                    Text("确认添加")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 2)
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.06))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
        )
    }
}

/// 单个解析任务行
private struct ParsedTaskRow: View {
    let task: ParsedTask

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // 第一行：标题 + 预估时间
            HStack(alignment: .firstTextBaseline) {
                Text(task.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
                Spacer()
                Text("\(task.estimatedMinutes)分钟")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            // 第二行：分类 + 优先级
            HStack(spacing: 8) {
                Label(task.category, systemImage: "folder")
                Label(task.priority.displayName + "优先级", systemImage: task.priority.iconName)
                    .foregroundStyle(priorityColor(task.priority))
                if task.recommended {
                    Label("AI 推荐", systemImage: "star.fill")
                        .foregroundStyle(.yellow)
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)

            // 第三行：AI 推荐理由
            if !task.reason.isEmpty {
                Text(task.reason)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary.opacity(0.8))
                    .lineLimit(2)
                    .padding(.leading, 2)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.4))
        .cornerRadius(4)
    }

    private func priorityColor(_ priority: TaskPriority) -> Color {
        switch priority {
        case .high: return .red
        case .medium: return .orange
        case .low: return .blue
        }
    }
}
