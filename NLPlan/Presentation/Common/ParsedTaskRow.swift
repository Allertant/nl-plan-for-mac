import SwiftUI

/// 单个解析任务行（含编辑/删除），供 QueueDetailView 和 InputSection 复用
struct ParsedTaskRow: View {
    let task: ParsedTask
    var isLocked: Bool = false
    let onEdit: (_ title: String, _ category: String, _ minutes: Int) -> Void
    let onDelete: () -> Void

    @State private var isEditing = false
    @State private var showDeleteConfirm = false
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
            HStack(alignment: .top) {
                Text(task.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

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
                    .disabled(isLocked)

                    if showDeleteConfirm {
                        Button {
                            showDeleteConfirm = false
                        } label: {
                            Text("取消")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .disabled(isLocked)

                        Button {
                            onDelete()
                        } label: {
                            Text("删除")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .disabled(isLocked)
                    } else {
                        Button {
                            showDeleteConfirm = true
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.red.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                        .help("删除")
                        .disabled(isLocked)
                    }
                }
            }

            HStack(spacing: 8) {
                Label(task.category, systemImage: "folder")
                Label(task.estimatedMinutes.hourMinuteString, systemImage: "clock")
                if task.recommended {
                    Label("AI 推荐", systemImage: "star.fill")
                        .foregroundStyle(.yellow)
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)

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
