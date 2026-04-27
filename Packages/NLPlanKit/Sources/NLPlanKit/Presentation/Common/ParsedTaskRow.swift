import SwiftUI

/// 单个解析任务行（点击内联编辑），供 QueueDetailView 复用
struct ParsedTaskRow: View {
    let task: ParsedTask
    var isLocked: Bool = false
    let onEdit: (_ title: String, _ category: String, _ minutes: Int?, _ note: String?) -> Void
    let onDelete: () -> Void
    let onApprove: () -> Void

    @State private var editingTitle = false
    @State private var editingMinutes = false
    @State private var editingNote = false
    @State private var showingCategoryMenu = false
    @State private var showDeleteConfirm = false
    @State private var draftTitle: String = ""
    @State private var draftMinutes: String = ""
    @State private var draftNote: String = ""
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case title, minutes, note }

    private var availableTags: [String] {
        UserDefaults.standard.stringArray(forKey: AppConstants.tagsKey) ?? AppConstants.defaultTags
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                // 标题行
                HStack(spacing: 4) {
                    if editingTitle {
                        TextField("任务标题", text: $draftTitle, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1...2)
                            .focused($focusedField, equals: .title)
                            .onSubmit { commitTitleEdit() }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(3)
                    } else {
                        Text(task.title)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(2)
                            .onTapGesture { startEditingTitle() }
                    }

                    if task.isProject == true {
                        Text("项目")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.indigo)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.indigo.opacity(0.12))
                            .cornerRadius(4)
                    }
                }

                // 分类 + 时长
                HStack(spacing: 8) {
                    Button { showingCategoryMenu.toggle() } label: {
                        TagChip(text: task.category)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingCategoryMenu, attachmentAnchor: .point(.bottom), arrowEdge: .top) {
                        categoryMenu
                    }

                    if task.isProject != true {
                        if editingMinutes {
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                TextField("1h30m", text: $draftMinutes)
                                    .textFieldStyle(.plain)
                                    .frame(width: 52)
                                    .focused($focusedField, equals: .minutes)
                                    .onSubmit { commitMinutesEdit() }
                            }
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(3)
                        } else if let estimatedMinutes = task.estimatedMinutes {
                            Label(estimatedMinutes.hourMinuteString, systemImage: "clock")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .onTapGesture { startEditingMinutes() }
                        }
                    }
                }

                // 备注
                if editingNote {
                    TextField("添加备注...", text: $draftNote)
                        .textFieldStyle(.plain)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .focused($focusedField, equals: .note)
                        .onSubmit { commitNoteEdit() }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(3)
                } else {
                    Text(task.note?.isEmpty ?? true ? "添加备注..." : task.note ?? "")
                        .font(.system(size: 10))
                        .foregroundStyle((task.note?.isEmpty ?? true) ? .tertiary : .secondary)
                        .onTapGesture { startEditingNote() }
                }
            }

            Spacer(minLength: 8)

            // 右侧操作
            VStack(spacing: 4) {
                Button {
                    onApprove()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                .help("通过")
                .disabled(isLocked)

                if showDeleteConfirm {
                    Button("取消") { showDeleteConfirm = false }
                        .buttonStyle(.plain)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Button("删除") { onDelete() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.red)
                } else {
                    Button { showDeleteConfirm = true } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundStyle(.red.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help("删除")
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .onChange(of: focusedField) { _, newValue in
            if newValue == nil {
                if editingTitle { commitTitleEdit() }
                if editingMinutes { commitMinutesEdit() }
                if editingNote { commitNoteEdit() }
            }
        }
    }

    // MARK: - 编辑操作

    private func startEditingTitle() {
        if editingMinutes { commitMinutesEdit() }
        if editingNote { commitNoteEdit() }
        draftTitle = task.title
        editingTitle = true
        focusedField = .title
    }

    private func commitTitleEdit() {
        editingTitle = false
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != task.title else { return }
        onEdit(trimmed, task.category, task.estimatedMinutes, task.note)
    }

    private func startEditingMinutes() {
        if editingTitle { commitTitleEdit() }
        if editingNote { commitNoteEdit() }
        draftMinutes = (task.estimatedMinutes ?? 30).hourMinuteString
        editingMinutes = true
        focusedField = .minutes
    }

    private func commitMinutesEdit() {
        editingMinutes = false
        let trimmed = draftMinutes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let minutes = trimmed.parsedHourMinuteDuration, minutes != task.estimatedMinutes else { return }
        onEdit(task.title, task.category, minutes, task.note)
    }

    private func startEditingNote() {
        if editingTitle { commitTitleEdit() }
        if editingMinutes { commitMinutesEdit() }
        draftNote = task.note ?? ""
        editingNote = true
        focusedField = .note
    }

    private func commitNoteEdit() {
        editingNote = false
        let trimmed = draftNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != (task.note ?? "") {
            onEdit(task.title, task.category, task.estimatedMinutes, trimmed)
        }
    }

    // MARK: - 分类菜单

    private var categoryMenu: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(availableTags, id: \.self) { tag in
                Button {
                    showingCategoryMenu = false
                    if tag != task.category {
                        onEdit(task.title, tag, task.estimatedMinutes, task.note)
                    }
                } label: {
                    HStack(spacing: 6) {
                        if tag == task.category {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                        } else {
                            Color.clear.frame(width: 10, height: 10)
                        }
                        TagChip(text: tag)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .frame(width: 180)
    }
}
