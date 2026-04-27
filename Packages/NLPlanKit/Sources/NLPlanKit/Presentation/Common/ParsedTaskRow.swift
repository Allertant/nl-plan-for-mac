import SwiftUI

/// 单个解析任务行（含编辑/删除/单独通过），供 QueueDetailView 复用
struct ParsedTaskRow: View {
    let task: ParsedTask
    var isLocked: Bool = false
    let onEdit: (_ title: String, _ category: String, _ minutes: Int?, _ note: String?) -> Void
    let onDelete: () -> Void
    let onApprove: () -> Void

    @State private var isEditing = false
    @State private var showDeleteConfirm = false
    @State private var editTitle: String = ""
    @State private var editCategory: String = ""
    @State private var editMinutes: String = ""
    @State private var editNote: String = ""

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
                        editMinutes = task.estimatedMinutes.map(String.init) ?? ""
                        editNote = task.note ?? ""
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
                if let estimatedMinutes = task.estimatedMinutes {
                    Label(estimatedMinutes.hourMinuteString, systemImage: "clock")
                }
                if task.isProject == true {
                    Label("项目", systemImage: "square.stack")
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)

            if let note = task.note, !note.isEmpty {
                Text(note)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // 单个通过按钮
            HStack {
                Spacer()
                Button {
                    onApprove()
                } label: {
                    Text("通过")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(isLocked)
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

                if task.isProject != true {
                    TextField("时长(分钟)", text: $editMinutes)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .frame(width: 70)
                }
            }

            TextField("备注", text: $editNote)
                .textFieldStyle(.plain)
                .font(.system(size: 11))

            HStack {
                Button("取消") {
                    isEditing = false
                }
                .buttonStyle(.borderless)
                .font(.system(size: 10))

                Spacer()

                Button("保存") {
                    let minutes = task.isProject == true ? nil : (Int(editMinutes) ?? task.estimatedMinutes ?? 30)
                    onEdit(editTitle, editCategory, minutes, editNote)
                    isEditing = false
                }
                .buttonStyle(.borderless)
                .font(.system(size: 10, weight: .medium))
                .disabled(editTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}
