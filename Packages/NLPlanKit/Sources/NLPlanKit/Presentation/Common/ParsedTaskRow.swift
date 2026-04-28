import SwiftUI

/// 单个解析任务行（点击内联编辑），供 QueueDetailView 复用
struct ParsedTaskRow: View {
    let task: ParsedTask
    var isLocked: Bool = false
    let onEdit: (_ title: String, _ category: String, _ minutes: Int?, _ note: String?, _ deadline: Date?, _ deadlineHasExplicitYear: Bool, _ deadlineHasTime: Bool) -> Void
    let onDelete: () -> Void
    let onApprove: () -> Void
    let onToggleProject: () -> Void

    @State private var editingTitle = false
    @State private var editingMinutes = false
    @State private var editingNote = false
    @State private var editingDeadline = false
    @State private var showingCategoryMenu = false
    @State private var showDeleteConfirm = false
    @State private var draftTitle: String = ""
    @State private var draftMinutes: String = ""
    @State private var draftNote: String = ""
    @State private var draftDeadline: String = ""
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case title, minutes, note, deadline }

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

                    Menu {
                        Button(task.isProject == true ? "设为普通想法" : "设为项目") { onToggleProject() }
                    } label: {
                        if task.isProject == true {
                            Text("项目")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.indigo)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.indigo.opacity(0.12))
                                .cornerRadius(4)
                        } else {
                            Image(systemName: "chevron.down.circle")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                }

                // 分类 + 时长 + 截止
                HStack(spacing: 8) {
                    Button { showingCategoryMenu.toggle() } label: {
                        TagChip(text: task.category)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingCategoryMenu, attachmentAnchor: .point(.bottom), arrowEdge: .top) {
                        CategoryPickerMenu(currentCategory: task.category) { tag in
                            showingCategoryMenu = false
                            if tag != task.category {
                                onEdit(task.title, tag, task.estimatedMinutes, task.note, task.deadline, task.deadlineHasExplicitYear, task.deadlineHasTime)
                            }
                        }
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

                    // 截止时间
                    if editingDeadline {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                            TextField("4-1 或 4-1 23:30", text: $draftDeadline)
                                .textFieldStyle(.plain)
                                .frame(width: 90)
                                .focused($focusedField, equals: .deadline)
                                .onSubmit { commitDeadlineEdit() }
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(3)
                    } else if let display = task.deadlineDisplayString {
                        Label(display, systemImage: "calendar")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .onTapGesture { startEditingDeadline() }
                    } else {
                        Label("添加截止...", systemImage: "calendar")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .onTapGesture { startEditingDeadline() }
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
        .background { Color(nsColor: .textBackgroundColor).contentShape(Rectangle()).onTapGesture { focusedField = nil } }
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
                if editingDeadline { commitDeadlineEdit() }
            }
        }
    }

    // MARK: - 编辑操作

    private func startEditingTitle() {
        if editingMinutes { commitMinutesEdit() }
        if editingNote { commitNoteEdit() }
        if editingDeadline { commitDeadlineEdit() }
        draftTitle = task.title
        editingTitle = true
        focusedField = .title
        CursorHelper.moveInsertionPointToEnd()
    }

    private func commitTitleEdit() {
        editingTitle = false
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != task.title else { return }
        onEdit(trimmed, task.category, task.estimatedMinutes, task.note, task.deadline, task.deadlineHasExplicitYear, task.deadlineHasTime)
    }

    private func startEditingMinutes() {
        if editingTitle { commitTitleEdit() }
        if editingNote { commitNoteEdit() }
        if editingDeadline { commitDeadlineEdit() }
        draftMinutes = (task.estimatedMinutes ?? 30).hourMinuteString
        editingMinutes = true
        focusedField = .minutes
        CursorHelper.moveInsertionPointToEnd()
    }

    private func commitMinutesEdit() {
        editingMinutes = false
        let trimmed = draftMinutes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let minutes = trimmed.parsedHourMinuteDuration, minutes != task.estimatedMinutes else { return }
        onEdit(task.title, task.category, minutes, task.note, task.deadline, task.deadlineHasExplicitYear, task.deadlineHasTime)
    }

    private func startEditingNote() {
        if editingTitle { commitTitleEdit() }
        if editingMinutes { commitMinutesEdit() }
        if editingDeadline { commitDeadlineEdit() }
        draftNote = task.note ?? ""
        editingNote = true
        focusedField = .note
        CursorHelper.moveInsertionPointToEnd()
    }

    private func commitNoteEdit() {
        editingNote = false
        let trimmed = draftNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != (task.note ?? "") {
            onEdit(task.title, task.category, task.estimatedMinutes, trimmed, task.deadline, task.deadlineHasExplicitYear, task.deadlineHasTime)
        }
    }

    private func startEditingDeadline() {
        if editingTitle { commitTitleEdit() }
        if editingMinutes { commitMinutesEdit() }
        if editingNote { commitNoteEdit() }
        draftDeadline = task.deadlineDisplayString ?? ""
        editingDeadline = true
        focusedField = .deadline
        CursorHelper.moveInsertionPointToEnd()
    }

    private func commitDeadlineEdit() {
        editingDeadline = false
        let trimmed = draftDeadline.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            // 清空截止时间
            if task.deadline != nil {
                onEdit(task.title, task.category, task.estimatedMinutes, task.note, nil, false, false)
            }
            return
        }
        let (parsed, hasExplicitYear, hasTime) = DeepSeekAIService.parseDeadlineString(trimmed)
        guard let parsed else { return }
        if parsed != task.deadline || hasExplicitYear != task.deadlineHasExplicitYear || hasTime != task.deadlineHasTime {
            onEdit(task.title, task.category, task.estimatedMinutes, task.note, parsed, hasExplicitYear, hasTime)
        }
    }
}
