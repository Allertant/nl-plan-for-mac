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
                    },
                    onEdit: { index, title, category, minutes in
                        viewModel.updateParsedTask(at: index, title: title, category: category, estimatedMinutes: minutes)
                    },
                    onDelete: { index in
                        viewModel.removeParsedTask(at: index)
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

// MARK: - 确认卡片

/// AI 解析结果确认卡片
private struct ParsedTaskConfirmation: View {
    let originalInput: String
    let parsedTasks: [ParsedTask]
    let onConfirm: () -> Void
    let onCancel: () -> Void
    let onEdit: (_ index: Int, _ title: String, _ category: String, _ minutes: Int) -> Void
    let onDelete: (_ index: Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)

            Divider()

            // 解析结果列表
            Text("AI 解析结果（\(parsedTasks.count) 个任务）")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            ForEach(Array(parsedTasks.enumerated()), id: \.element.id) { index, task in
                ParsedTaskRow(
                    task: task,
                    onEdit: { title, category, minutes in
                        onEdit(index, title, category, minutes)
                    },
                    onDelete: {
                        onDelete(index)
                    }
                )
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
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - 单个任务行

/// 单个解析任务行（含编辑/删除）
private struct ParsedTaskRow: View {
    let task: ParsedTask
    let onEdit: (_ title: String, _ category: String, _ minutes: Int) -> Void
    let onDelete: () -> Void

    @State private var isEditing = false
    @State private var editTitle: String = ""
    @State private var editCategory: String = ""
    @State private var editMinutes: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isEditing {
                editBody
            } else {
                viewBody
            }
        }
        .padding(8)
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - 查看态

    private var viewBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 第一行：标题 + 操作按钮
            HStack(alignment: .top) {
                Text(task.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                // 编辑/删除按钮
                HStack(spacing: 4) {
                    Button {
                        editTitle = task.title
                        editCategory = task.category
                        editMinutes = String(task.estimatedMinutes)
                        isEditing = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("编辑")

                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.red.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .help("删除")
                }
            }

            // 第二行：分类 + 预估时长 + 推荐
            HStack(spacing: 8) {
                Label(task.category, systemImage: "folder")
                Label("\(task.estimatedMinutes)分钟", systemImage: "clock")
                if task.recommended {
                    Label("AI 推荐", systemImage: "star.fill")
                        .foregroundStyle(.yellow)
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)

            // 第三行：推荐理由
            if !task.reason.isEmpty {
                Text(task.reason)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary.opacity(0.8))
                    .lineLimit(2)
                    .padding(.leading, 2)
            }
        }
    }

    // MARK: - 编辑态

    private var editBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("任务名称", text: $editTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 12))

            HStack(spacing: 8) {
                TextField("分类", text: $editCategory)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .frame(width: 80)

                TextField("时长(分钟)", text: $editMinutes)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .frame(width: 70)
            }

            HStack {
                Button("取消") {
                    isEditing = false
                }
                .buttonStyle(.borderless)
                .font(.system(size: 10))

                Spacer()

                Button("保存") {
                    let minutes = Int(editMinutes) ?? task.estimatedMinutes
                    onEdit(editTitle, editCategory, minutes)
                    isEditing = false
                }
                .buttonStyle(.borderless)
                .font(.system(size: 10, weight: .medium))
                .disabled(editTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}
