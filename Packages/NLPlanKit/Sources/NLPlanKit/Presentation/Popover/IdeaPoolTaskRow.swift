import AppKit
import SwiftUI

/// 想法池单行卡片（含内联编辑、项目进度、分类切换等）
struct IdeaPoolTaskRow: View {
    let idea: IdeaEntity
    var isNew: Bool = false
    var isRefreshingProject: Bool = false
    let onPromote: (TaskPriority) -> Void
    let onDelete: () -> Void
    let onUpdate: (_ title: String?, _ category: String?, _ estimatedMinutes: Int?, _ note: String?) -> Void
    let onRefreshProject: () -> Void
    let onUpdateProjectState: (Bool) -> Void
    let onOpenProject: () -> Void

    @State private var flashCount = 0
    @State private var showDeleteConfirm = false
    @State private var editingTitle = false
    @State private var editingMinutes = false
    @State private var editingNote = false
    @State private var showingCategoryMenu = false
    @State private var draftTitle: String = ""
    @State private var draftMinutes: String = ""
    @State private var draftNote: String = ""
    @FocusState private var focusedField: Field?
    private var isInProgress: Bool { idea.ideaStatus == .inProgress }

    private enum Field: Hashable { case title, minutes, note }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    if !idea.isProject && editingTitle {
                        TextField("任务标题", text: $draftTitle, axis: .vertical).textFieldStyle(.plain).font(.system(size: 12, weight: .medium)).lineLimit(1...2)
                            .focused($focusedField, equals: .title).onSubmit { commitTitleEdit() }
                            .padding(.horizontal, 4).padding(.vertical, 2).background(Color.accentColor.opacity(0.1)).cornerRadius(3)
                    } else {
                        Text(idea.title).font(.system(size: 12, weight: .medium)).lineLimit(2).onTapGesture { if !idea.isProject { startEditingTitle() } }
                    }
                    if idea.aiRecommended { Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(.orange) }
                    Menu {
                        Button(idea.isProject ? "设为普通想法" : "设为项目") { onUpdateProjectState(!idea.isProject) }
                    } label: {
                        if idea.isProject {
                            Text("项目").font(.system(size: 9, weight: .medium)).foregroundStyle(.indigo).padding(.horizontal, 5).padding(.vertical, 1).background(Color.indigo.opacity(0.12)).cornerRadius(4)
                        } else {
                            Image(systemName: "chevron.down.circle").font(.system(size: 10)).foregroundStyle(.tertiary)
                        }
                    }.menuStyle(.borderlessButton).menuIndicator(.hidden)
                    if !idea.isProject && idea.attempted { Text("已尝试").font(.system(size: 9)).foregroundStyle(.orange).padding(.horizontal, 4).padding(.vertical, 1).background(Color.orange.opacity(0.15)).cornerRadius(3) }
                    if isInProgress { Text("进行中").font(.system(size: 9, weight: .medium)).foregroundStyle(.green).padding(.horizontal, 4).padding(.vertical, 1).background(Color.green.opacity(0.14)).cornerRadius(3) }
                }
                HStack(spacing: 8) {
                    Button { showingCategoryMenu.toggle() } label: { TagChip(text: idea.category) }.buttonStyle(.plain)
                        .popover(isPresented: $showingCategoryMenu, attachmentAnchor: .point(.bottom), arrowEdge: .top) {
                            CategoryPickerMenu(currentCategory: idea.category) { tag in
                                showingCategoryMenu = false
                                if tag != idea.category { onUpdate(nil, tag, nil, nil) }
                            }
                        }
                    if idea.isProject { EmptyView() }
                    else if editingMinutes {
                        HStack(spacing: 4) { Image(systemName: "clock"); TextField("1h30m", text: $draftMinutes).textFieldStyle(.plain).frame(width: 52).focused($focusedField, equals: .minutes).onSubmit { commitMinutesEdit() } }
                            .font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 4).padding(.vertical, 2).background(Color.accentColor.opacity(0.1)).cornerRadius(3)
                    } else {
                        if let estimatedMinutes = idea.estimatedMinutes {
                            Label(estimatedMinutes.hourMinuteString, systemImage: "clock").font(.system(size: 10)).foregroundStyle(.secondary).onTapGesture { startEditingMinutes() }
                        }
                    }
                    Text(idea.createdDate.relativeTimeString()).font(.system(size: 10)).foregroundStyle(.tertiary)
                    if let deadlineDisplay = idea.deadlineDisplayString {
                        Label(deadlineDisplay, systemImage: "calendar").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                if idea.aiRecommended, let reason = idea.recommendationReason, !reason.isEmpty { TooltipText(text: "💡 \(reason)", tooltip: reason) }
                if idea.isProject {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            ProgressView(value: (idea.projectProgress ?? 0) / 100).progressViewStyle(.linear).tint(.indigo)
                            Text("\(Int(idea.projectProgress ?? 0))%").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                            Button(action: onRefreshProject) { RefreshingIcon(systemName: "arrow.clockwise", isAnimating: isRefreshingProject).font(.system(size: 10)).foregroundStyle(.indigo) }
                                .buttonStyle(.plain).disabled(isRefreshingProject).help("刷新项目进度")
                        }
                        if let summary = idea.projectProgressSummary, !summary.isEmpty { Text(summary).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2) }
                    }
                }
                if !idea.isProject {
                    if editingNote {
                        TextField("添加备注...", text: $draftNote).textFieldStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary)
                            .focused($focusedField, equals: .note).onSubmit { commitNoteEdit() }
                            .padding(.horizontal, 4).padding(.vertical, 2).background(Color.accentColor.opacity(0.1)).cornerRadius(3)
                    } else {
                        Text(idea.note?.isEmpty ?? true ? "添加备注..." : idea.note ?? "").font(.system(size: 10))
                            .foregroundStyle((idea.note?.isEmpty ?? true) ? .tertiary : .secondary).onTapGesture { startEditingNote() }
                    }
                }
            }
            Spacer(minLength: 12)
            VStack(spacing: 4) {
                Menu {
                    ForEach(TaskPriority.allCases, id: \.self) { priority in
                        Button { onPromote(priority) } label: { Label("优先级：\(priority.displayName)", systemImage: priority == .high ? "flag.fill" : "flag") }
                    }
                } label: { Image(systemName: "plus.circle.fill").font(.system(size: 16)).foregroundStyle(.green) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).help("加入必做项").disabled(isInProgress).opacity(isInProgress ? 0.35 : 1)
                if showDeleteConfirm {
                    Button("取消") { showDeleteConfirm = false }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary)
                    Button("删除") { onDelete() }.buttonStyle(.plain).font(.system(size: 10, weight: .medium)).foregroundStyle(.red)
                } else {
                    Button { showDeleteConfirm = true } label: { Image(systemName: "trash").font(.system(size: 12)).foregroundStyle(.red.opacity(0.6)) }
                        .buttonStyle(.plain).help("删除")
                }
            }
        }
        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        .background { rowBackground.contentShape(Rectangle()).onTapGesture { focusedField = nil; if idea.isProject { onOpenProject() } } }
        .cornerRadius(6)
        .onChange(of: focusedField) { _, newValue in
            if newValue == nil { if editingTitle { commitTitleEdit() }; if editingMinutes { commitMinutesEdit() }; if editingNote { commitNoteEdit() } }
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

    private var rowBackground: Color {
        if flashCount % 2 == 1 { return Color.accentColor.opacity(0.15) }
        if idea.isProject {
            if isInProgress { return Color.indigo.opacity(0.10) }
            return Color.indigo.opacity(0.06)
        }
        if isInProgress { return Color.green.opacity(0.10) }
        return Color.blue.opacity(0.05)
    }

    private func startEditingTitle() { if editingNote { commitNoteEdit() }; if editingMinutes { commitMinutesEdit() }; draftTitle = idea.title; editingTitle = true; focusedField = .title; CursorHelper.moveInsertionPointToEnd() }
    private func commitTitleEdit() { editingTitle = false; let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines); guard !trimmed.isEmpty, trimmed != idea.title else { return }; onUpdate(trimmed, nil, nil, nil) }
    private func startEditingMinutes() { if editingTitle { commitTitleEdit() }; if editingNote { commitNoteEdit() }; draftMinutes = (idea.estimatedMinutes ?? 30).hourMinuteString; editingMinutes = true; focusedField = .minutes; CursorHelper.moveInsertionPointToEnd() }
    private func commitMinutesEdit() { editingMinutes = false; let trimmed = draftMinutes.trimmingCharacters(in: .whitespacesAndNewlines); guard let minutes = trimmed.parsedHourMinuteDuration, minutes != idea.estimatedMinutes else { return }; onUpdate(nil, nil, minutes, nil) }
    private func startEditingNote() { if editingTitle { commitTitleEdit() }; if editingMinutes { commitMinutesEdit() }; draftNote = idea.note ?? ""; editingNote = true; focusedField = .note; CursorHelper.moveInsertionPointToEnd() }
    private func commitNoteEdit() { editingNote = false; let trimmed = draftNote.trimmingCharacters(in: .whitespacesAndNewlines); if trimmed != (idea.note ?? "") { onUpdate(nil, nil, nil, trimmed) } }
}
