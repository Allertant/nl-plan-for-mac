import SwiftUI

/// 想法池区域
struct IdeaPoolSection: View {
    @Bindable var viewModel: IdeaPoolViewModel
    @State private var searchText: String = ""

    private var filteredTasks: [TaskEntity] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return viewModel.tasks }
        return viewModel.tasks.filter { $0.title.localizedCaseInsensitiveContains(keyword) }
    }

    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            // 折叠头部
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.yellow)
                    Text("想法池")
                        .font(.system(size: 13, weight: .semibold))
                    if !viewModel.tasks.isEmpty {
                        Text("\(viewModel.tasks.count)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                    }
                    Spacer()
                    Image(systemName: viewModel.isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            VStack(spacing: 0) {
                Divider()

                if viewModel.tasks.isEmpty {
                    Text("暂无想法")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 16)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        TextField("搜索计划名称", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))

                        Text("\(filteredTasks.count)条")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)

                        cleanupButton
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
                    .padding(.horizontal, 8)
                    .padding(.top, 6)

                    if filteredTasks.isEmpty {
                        Text("未找到匹配的计划")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 16)
                    } else {
                        LazyVStack(spacing: 4) {
                            ForEach(filteredTasks, id: \.id) { task in
                                IdeaPoolTaskRow(task: task, isNew: viewModel.newlyAddedTaskIds.contains(task.id)) { priority in
                                    Task { await viewModel.promoteToMustDo(taskId: task.id, priority: priority) }
                                } onDelete: {
                                    Task { await viewModel.deleteTask(taskId: task.id) }
                                } onUpdate: { title, category, note in
                                    Task { await viewModel.updateTask(taskId: task.id, title: title, category: category, note: note) }
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                    }
                }
            }
            .frame(maxHeight: viewModel.isExpanded ? .infinity : 0)
            .clipped()
            .opacity(viewModel.isExpanded ? 1 : 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.08))
        .cornerRadius(8)
    }

    // MARK: - 清理按钮

    private var cleanupButton: some View {
        Group {
            switch viewModel.cleanupState {
            case .idle:
                Button {
                    Task { await viewModel.fetchCleanupSuggestions() }
                } label: {
                    Image(systemName: "paintbrush")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .help("AI 清理")

            case .loading:
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 16, height: 16)

            case .loaded:
                Button {
                    appState.currentPage = .cleanupDetail
                } label: {
                    Image(systemName: "paintbrush")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .help("查看清理建议")

            case .error:
                Button {
                    Task { await viewModel.fetchCleanupSuggestions() }
                } label: {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("重试 AI 清理")
            }
        }
    }
}

struct IdeaPoolTaskRow: View {
    let task: TaskEntity
    var isNew: Bool = false
    let onPromote: (TaskPriority) -> Void
    let onDelete: () -> Void
    let onUpdate: (_ title: String?, _ category: String?, _ note: String?) -> Void

    @State private var flashCount = 0
    @State private var showDeleteConfirm = false
    @State private var editingTitle = false
    @State private var editingNote = false
    @State private var showingCategoryMenu = false
    @State private var draftTitle: String = ""
    @State private var draftNote: String = ""
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case title, note
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                // 标题行
                HStack(spacing: 4) {
                    if editingTitle {
                        TextField("任务标题", text: $draftTitle)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, weight: .medium))
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

                    if task.aiRecommended {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                    }

                    if task.attempted {
                        Text("已尝试")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.15))
                            .cornerRadius(3)
                    }
                }

                // 标签 + 时长 + 日期
                HStack(spacing: 8) {
                    Button {
                        showingCategoryMenu.toggle()
                    } label: {
                        TagChip(text: task.category)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingCategoryMenu, attachmentAnchor: .point(.bottom), arrowEdge: .top) {
                        categoryMenu
                    }

                    Label("\(task.estimatedMinutes)分钟", systemImage: "clock")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    Text(task.createdDate.dateString)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                // AI 推荐理由
                if task.aiRecommended, let reason = task.recommendationReason {
                    TooltipText(text: "💡 \(reason)", tooltip: reason)
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

            Spacer()

            VStack(spacing: 4) {
                Menu {
                    ForEach(TaskPriority.allCases, id: \.self) { priority in
                        Button {
                            onPromote(priority)
                        } label: {
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

                if showDeleteConfirm {
                    Button {
                        showDeleteConfirm = false
                    } label: {
                        Text("取消")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Button {
                        onDelete()
                    } label: {
                        Text("删除")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        showDeleteConfirm = true
                    } label: {
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
        .background(flashCount % 2 == 1 ? Color.accentColor.opacity(0.15) : Color(nsColor: .textBackgroundColor))
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onTapGesture {
            focusedField = nil
        }
        .onChange(of: focusedField) { _, newValue in
            if newValue == nil {
                if editingTitle { commitTitleEdit() }
                if editingNote { commitNoteEdit() }
            }
        }
        .onAppear {
            if isNew {
                // 闪烁两次
                withAnimation(.easeInOut(duration: 0.3)) {
                    flashCount = 1
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        flashCount = 0
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        flashCount = 1
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        flashCount = 0
                    }
                }
            }
        }
    }

    // MARK: - Inline Editing

    private func startEditingTitle() {
        // 如果正在编辑备注，先提交备注
        if editingNote {
            commitNoteEdit()
        }
        draftTitle = task.title
        editingTitle = true
        focusedField = .title
    }

    private func commitTitleEdit() {
        editingTitle = false
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != task.title else { return }
        onUpdate(trimmed, nil, nil)
    }

    private func startEditingNote() {
        // 如果正在编辑标题，先提交标题
        if editingTitle {
            commitTitleEdit()
        }
        draftNote = task.note ?? ""
        editingNote = true
        focusedField = .note
    }

    private func commitNoteEdit() {
        editingNote = false
        let trimmed = draftNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != (task.note ?? "") {
            onUpdate(nil, nil, trimmed)
        }
    }

    private var availableTags: [String] {
        UserDefaults.standard.stringArray(forKey: AppConstants.tagsKey) ?? AppConstants.defaultTags
    }

    private var categoryMenu: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(availableTags, id: \.self) { tag in
                Button {
                    showingCategoryMenu = false
                    if tag != task.category {
                        onUpdate(nil, tag, nil)
                    }
                } label: {
                    HStack(spacing: 6) {
                        if tag == task.category {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                        } else {
                            Color.clear
                                .frame(width: 10, height: 10)
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
