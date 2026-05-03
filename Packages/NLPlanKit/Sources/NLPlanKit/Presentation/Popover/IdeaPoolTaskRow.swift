import AppKit
import SwiftUI

/// 想法池单行卡片（普通想法专用）
struct IdeaPoolTaskRow: View {
    let idea: IdeaEntity
    var isNew: Bool = false
    let onTogglePin: () -> Void
    let onPromote: (TaskPriority) -> Void
    let onDelete: () -> Void
    let onUpdate: (_ title: String?, _ category: String?, _ estimatedMinutes: Int?, _ note: String?, _ deadline: Date?) -> Void

    @State private var flashCount = 0
    @State private var editingTitle = false
    @State private var editingMinutes = false
    @State private var editingNote = false
    @State private var showingCategoryMenu = false
    @State private var draftTitle: String = ""
    @State private var draftMinutes: String = ""
    @State private var draftNote: String = ""
    @State private var editingDeadline = false
    @State private var draftDeadline: String = ""
    @FocusState private var focusedField: Field?
    @State private var cachedRelativeTime: String = ""
    @State private var cachedDeadlineDisplay: String?

    private var isInProgress: Bool { idea.ideaStatus == .inProgress }

    private enum Field: Hashable { case title, minutes, note, deadline }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 行 1：标题 + 加入必做项按钮
            HStack(spacing: 4) {
                titleView
                statusIndicators
                Spacer(minLength: 8)
                pinButton
                promoteMenu
            }

            // 行 2：标签/时间/截止日期 + 删除按钮
            HStack(spacing: 8) {
                categoryButton
                    .popover(isPresented: $showingCategoryMenu, attachmentAnchor: .point(.bottom), arrowEdge: .top) {
                        CategoryPickerMenu(currentCategory: idea.category) { tag in
                            showingCategoryMenu = false
                            if tag != idea.category { onUpdate(nil, tag, nil, nil, nil) }
                        }
                    }
                minutesView
                Text(cachedRelativeTime).font(.system(size: 10)).foregroundStyle(.tertiary)
                deadlineView
                Spacer(minLength: 8)
                HoverIconButton(icon: "trash", color: .red.opacity(0.6), action: onDelete)
                    .help("删除")
            }

            // 行 3：备注
            if editingNote {
                TextField("添加备注...", text: $draftNote, axis: .vertical).textFieldStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary)
                    .focused($focusedField, equals: .note).onSubmit { commitNoteEdit() }
                    .padding(.horizontal, 4).padding(.vertical, 2).background(Color.accentColor.opacity(0.1)).cornerRadius(3)
            } else {
                Text(idea.note?.isEmpty ?? true ? "添加备注..." : idea.note ?? "").font(.system(size: 10))
                    .foregroundStyle((idea.note?.isEmpty ?? true) ? .tertiary : .secondary).onTapGesture { startEditingNote() }
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background { rowBackground.contentShape(Rectangle()).onTapGesture { focusedField = nil } }
        .cornerRadius(6)
        .overlay {
            if idea.isPinned {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.accentColor.opacity(0.45), lineWidth: 1.5)
            }
        }
        .onChange(of: focusedField) { _, newValue in
            if newValue == nil { if editingTitle { commitTitleEdit() }; if editingMinutes { commitMinutesEdit() }; if editingNote { commitNoteEdit() }; if editingDeadline { commitDeadlineEdit() } }
        }
        .onAppear {
            cachedRelativeTime = idea.createdDate.relativeTimeString()
            cachedDeadlineDisplay = idea.deadlineDisplayString
        }
        .onChange(of: idea.deadline) { _, _ in
            cachedDeadlineDisplay = idea.deadlineDisplayString
        }
        .onAppear {
            if isNew {
                withAnimation(.easeInOut(duration: 0.3)) { flashCount = 1 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { withAnimation(.easeInOut(duration: 0.3)) { flashCount = 0 } }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { withAnimation(.easeInOut(duration: 0.3)) { flashCount = 1 } }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { withAnimation(.easeInOut(duration: 0.3)) { flashCount = 0 } }
            }
        }
    }

    // MARK: - Background

    private var rowBackground: Color {
        if flashCount % 2 == 1 { return Color.accentColor.opacity(0.15) }
        if isInProgress { return Color.green.opacity(0.10) }
        return Color.blue.opacity(0.05)
    }

    private var titleView: some View {
        Group {
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
                Text(idea.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
                    .onTapGesture { startEditingTitle() }
            }
        }
    }

    private var pinButton: some View {
        HoverIconButton(
            icon: idea.isPinned ? "pin.fill" : "pin",
            iconSize: 14,
            color: idea.isPinned ? Color.accentColor : Color.secondary,
            action: onTogglePin
        )
        .help(idea.isPinned ? "取消置顶" : "置顶")
    }

    private var statusIndicators: some View {
        HStack(spacing: 4) {
            if idea.aiRecommended {
                Image(systemName: "star.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
            }
            if idea.attempted {
                attemptedBadge
            }
            if isInProgress {
                inProgressBadge
            }
            if idea.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    private var promoteMenu: some View {
        Menu {
            ForEach(TaskPriority.allCases, id: \.self) { priority in
                Button { onPromote(priority) } label: {
                    Label("优先级：\(priority.displayName)", systemImage: priority == .high ? "flag.fill" : "flag")
                }
            }
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.green)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("加入必做项")
        .disabled(isInProgress)
        .opacity(isInProgress ? 0.35 : 1)
    }

    private var categoryButton: some View {
        Button { showingCategoryMenu.toggle() } label: {
            TagChip(text: idea.category)
        }
        .buttonStyle(.plain)
    }

    private var minutesView: some View {
        Group {
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
            } else if let estimatedMinutes = idea.estimatedMinutes {
                Label(estimatedMinutes.hourMinuteString, systemImage: "clock")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .onTapGesture { startEditingMinutes() }
            }
        }
    }

    private var deadlineView: some View {
        Group {
            if editingDeadline {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                    TextField("M-d", text: $draftDeadline)
                        .textFieldStyle(.plain)
                        .frame(width: 72)
                        .focused($focusedField, equals: .deadline)
                        .onSubmit { commitDeadlineEdit() }
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(3)
            } else if let deadlineDisplay = cachedDeadlineDisplay {
                Label(deadlineDisplay, systemImage: "calendar")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .onTapGesture { startEditingDeadline() }
            }
        }
    }

    private var attemptedBadge: some View {
        Text("已尝试")
            .font(.system(size: 9))
            .foregroundStyle(.orange)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color.orange.opacity(0.15))
            .cornerRadius(3)
    }

    private var inProgressBadge: some View {
        Text("进行中")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.green)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color.green.opacity(0.14))
            .cornerRadius(3)
    }

    // MARK: - Edit Helpers

    private func startEditingTitle() { if editingNote { commitNoteEdit() }; if editingMinutes { commitMinutesEdit() }; if editingDeadline { commitDeadlineEdit() }; draftTitle = idea.title; editingTitle = true; focusedField = .title; CursorHelper.moveInsertionPointToEnd() }
    private func commitTitleEdit() { editingTitle = false; let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines); guard !trimmed.isEmpty, trimmed != idea.title else { return }; onUpdate(trimmed, nil, nil, nil, nil) }
    private func startEditingMinutes() { if editingTitle { commitTitleEdit() }; if editingNote { commitNoteEdit() }; if editingDeadline { commitDeadlineEdit() }; draftMinutes = (idea.estimatedMinutes ?? 30).hourMinuteString; editingMinutes = true; focusedField = .minutes; CursorHelper.moveInsertionPointToEnd() }
    private func commitMinutesEdit() {
        editingMinutes = false
        let trimmed = draftMinutes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let minutes = trimmed.parsedHourMinuteDuration else { return }
        guard minutes != idea.estimatedMinutes else { return }
        onUpdate(nil, nil, minutes, nil, nil)
    }
    private func startEditingNote() { if editingTitle { commitTitleEdit() }; if editingMinutes { commitMinutesEdit() }; if editingDeadline { commitDeadlineEdit() }; draftNote = idea.note ?? ""; editingNote = true; focusedField = .note; CursorHelper.moveInsertionPointToEnd() }
    private func commitNoteEdit() { editingNote = false; let trimmed = draftNote.trimmingCharacters(in: .whitespacesAndNewlines); if trimmed != (idea.note ?? "") { onUpdate(nil, nil, nil, trimmed, nil) } }
    private func startEditingDeadline() { if editingTitle { commitTitleEdit() }; if editingMinutes { commitMinutesEdit() }; if editingNote { commitNoteEdit() }; draftDeadline = idea.deadlineDisplayString ?? ""; editingDeadline = true; focusedField = .deadline; CursorHelper.moveInsertionPointToEnd() }
    private func commitDeadlineEdit() {
        editingDeadline = false
        let trimmed = draftDeadline.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty || isValidDeadlineFormat(trimmed) else { return }
        let (parsed, _, _) = DeepSeekAIService.parseDeadlineString(trimmed.isEmpty ? nil : trimmed)
        if parsed != idea.deadline {
            onUpdate(nil, nil, nil, nil, parsed)
        }
    }

    // MARK: - Validation

    private func isValidDeadlineFormat(_ string: String) -> Bool {
        let parts = string.split(separator: " ", omittingEmptySubsequences: true)
        guard let datePart = parts.first else { return false }

        let dateComps = datePart.split(separator: "-").compactMap { Int($0) }
        guard dateComps.count == 2 || dateComps.count == 3 else { return false }

        if dateComps.count == 2 {
            guard dateComps[0] >= 1 && dateComps[0] <= 12,
                  dateComps[1] >= 1 && dateComps[1] <= 31 else { return false }
        } else {
            guard dateComps[0] >= 1,
                  dateComps[1] >= 1 && dateComps[1] <= 12,
                  dateComps[2] >= 1 && dateComps[2] <= 31 else { return false }
        }

        if parts.count > 1 {
            let timeComps = String(parts[1]).split(separator: ":").compactMap { Int($0) }
            guard timeComps.count >= 1 && timeComps.count <= 2 else { return false }
            guard timeComps[0] >= 0 && timeComps[0] <= 23 else { return false }
            if timeComps.count == 2 {
                guard timeComps[1] >= 0 && timeComps[1] <= 59 else { return false }
            }
        }

        return true
    }
}

// MARK: - Project Pool Row

struct ProjectPoolRow: View {
    let project: ProjectEntity
    var isRefreshing: Bool = false
    let onTogglePin: () -> Void
    let onPromote: (TaskPriority) -> Void
    let onDelete: () -> Void
    let onRefresh: () -> Void
    let onOpenDetail: () -> Void
    let onUpdate: (_ title: String?, _ category: String?, _ deadline: Date?) -> Void

    @State private var editingTitle = false
    @State private var showingCategoryMenu = false
    @State private var editingDeadline = false
    @State private var draftTitle: String = ""
    @State private var draftDeadline: String = ""
    @State private var projectRefreshHovered = false
    @State private var detailButtonHovered = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case title, deadline }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                if editingTitle {
                    TextField("项目标题", text: $draftTitle, axis: .vertical)
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
                    Text(project.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(2)
                        .onTapGesture { startEditingTitle() }
                }
                Text("项目").font(.system(size: 9, weight: .medium)).foregroundStyle(.indigo).padding(.horizontal, 5).padding(.vertical, 1).background(Color.indigo.opacity(0.12)).cornerRadius(4)
                if project.isPinned { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.indigo) }
                Spacer(minLength: 8)
                HoverIconButton(
                    icon: project.isPinned ? "pin.fill" : "pin",
                    iconSize: 14,
                    color: project.isPinned ? .indigo : .secondary,
                    action: onTogglePin
                )
                .help(project.isPinned ? "取消置顶" : "置顶")
                Menu {
                    ForEach(TaskPriority.allCases, id: \.self) { priority in
                        Button { onPromote(priority) } label: { Label("优先级：\(priority.displayName)", systemImage: priority == .high ? "flag.fill" : "flag") }
                    }
                } label: { Image(systemName: "plus.circle.fill").font(.system(size: 16)).foregroundStyle(.green) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).help("加入必做项")
            }

            HStack(spacing: 8) {
                Button { showingCategoryMenu.toggle() } label: {
                    TagChip(text: project.category)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingCategoryMenu, attachmentAnchor: .point(.bottom), arrowEdge: .top) {
                    CategoryPickerMenu(currentCategory: project.category) { tag in
                        showingCategoryMenu = false
                        if tag != project.category { onUpdate(nil, tag, nil) }
                    }
                }
                Text(project.createdDate.relativeTimeString()).font(.system(size: 10)).foregroundStyle(.tertiary)
                if editingDeadline {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                        TextField("M-d", text: $draftDeadline)
                            .textFieldStyle(.plain)
                            .frame(width: 72)
                            .focused($focusedField, equals: .deadline)
                            .onSubmit { commitDeadlineEdit() }
                    }
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.1)).cornerRadius(3)
                } else if let deadlineDisplay = project.deadlineDisplayString {
                    Label(deadlineDisplay, systemImage: "calendar")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .onTapGesture { startEditingDeadline() }
                }
                Spacer(minLength: 8)
                HoverIconButton(icon: "trash", color: .red.opacity(0.6), action: onDelete)
                    .help("删除")
            }

            HStack(spacing: 6) {
                ProgressView(value: (project.projectProgress ?? 0) / 100).progressViewStyle(.linear).tint(.indigo)
                Text("\(Int(project.projectProgress ?? 0))%").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                Button(action: onRefresh) { RefreshingIcon(systemName: "arrow.clockwise", isAnimating: isRefreshing).font(.system(size: 10)).foregroundStyle(.indigo).padding(4).contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .background(RoundedRectangle(cornerRadius: 4).fill(projectRefreshHovered ? Color.primary.opacity(0.08) : .clear))
                    .onHover { projectRefreshHovered = $0 }
                    .disabled(isRefreshing).help("刷新项目进度")
                Spacer(minLength: 8)
                Button("详情") { onOpenDetail() }
                    .font(.system(size: 10)).foregroundStyle(.blue)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(detailButtonHovered ? Color.primary.opacity(0.08) : .clear)
                    )
                    .onHover { detailButtonHovered = $0 }
            }
            if let summary = project.projectProgressSummary, !summary.isEmpty {
                Text(summary).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background { Color.indigo.opacity(0.06).contentShape(Rectangle()).onTapGesture { focusedField = nil } }
        .cornerRadius(6)
        .overlay {
            if project.isPinned {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.indigo.opacity(0.55), lineWidth: 1.5)
            }
        }
        .onChange(of: focusedField) { _, newValue in
            if newValue == nil {
                if editingTitle { commitTitleEdit() }
                if editingDeadline { commitDeadlineEdit() }
            }
        }
    }

    private func startEditingTitle() {
        if editingDeadline { commitDeadlineEdit() }
        draftTitle = project.title
        editingTitle = true
        focusedField = .title
        CursorHelper.moveInsertionPointToEnd()
    }

    private func commitTitleEdit() {
        editingTitle = false
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != project.title else { return }
        onUpdate(trimmed, nil, nil)
    }

    private func startEditingDeadline() {
        if editingTitle { commitTitleEdit() }
        draftDeadline = project.deadlineDisplayString ?? ""
        editingDeadline = true
        focusedField = .deadline
        CursorHelper.moveInsertionPointToEnd()
    }

    private func commitDeadlineEdit() {
        editingDeadline = false
        let trimmed = draftDeadline.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty || isValidDeadlineFormat(trimmed) else { return }
        let (parsed, _, _) = DeepSeekAIService.parseDeadlineString(trimmed.isEmpty ? nil : trimmed)
        if parsed != project.deadline {
            onUpdate(nil, nil, parsed)
        }
    }

    private func isValidDeadlineFormat(_ string: String) -> Bool {
        let parts = string.split(separator: " ", omittingEmptySubsequences: true)
        guard let datePart = parts.first else { return false }

        let dateComps = datePart.split(separator: "-").compactMap { Int($0) }
        guard dateComps.count == 2 || dateComps.count == 3 else { return false }

        if dateComps.count == 2 {
            guard dateComps[0] >= 1 && dateComps[0] <= 12,
                  dateComps[1] >= 1 && dateComps[1] <= 31 else { return false }
        } else {
            guard dateComps[0] >= 1,
                  dateComps[1] >= 1 && dateComps[1] <= 12,
                  dateComps[2] >= 1 && dateComps[2] <= 31 else { return false }
        }

        if parts.count > 1 {
            let timeComps = String(parts[1]).split(separator: ":").compactMap { Int($0) }
            guard timeComps.count >= 1 && timeComps.count <= 2 else { return false }
            guard timeComps[0] >= 0 && timeComps[0] <= 23 else { return false }
            if timeComps.count == 2 {
                guard timeComps[1] >= 0 && timeComps[1] <= 59 else { return false }
            }
        }

        return true
    }
}
