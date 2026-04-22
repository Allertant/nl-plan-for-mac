import AppKit
import SwiftUI

/// 想法池区域
struct IdeaPoolSection: View {
    @Bindable var viewModel: IdeaPoolViewModel
    @State private var searchText: String = ""
    @State private var selectedSearchTags: [String] = []
    @State private var highlightedTag: String?
    @FocusState private var isSearchFieldFocused: Bool

    private var filteredTasks: [TaskEntity] {
        let keyword = plainSearchKeyword
        let hasKeyword = !keyword.isEmpty
        let hasTags = !selectedSearchTags.isEmpty
        guard hasKeyword || hasTags else { return viewModel.tasks }

        return viewModel.tasks.filter { task in
            let matchesKeyword = !hasKeyword || task.title.localizedCaseInsensitiveContains(keyword)
            let matchesTag = !hasTags || selectedSearchTags.contains(task.category)
            return matchesKeyword && matchesTag
        }
    }

    private var availableTags: [String] {
        UserDefaults.standard.stringArray(forKey: AppConstants.tagsKey) ?? AppConstants.defaultTags
    }

    private var activeTagQuery: String? {
        let text = searchText
        guard let percentIndex = text.lastIndex(of: "%") else { return nil }

        let prefix = text[..<percentIndex]
        if let lastPrefix = prefix.last, !lastPrefix.isWhitespace {
            return nil
        }

        let suffixStart = text.index(after: percentIndex)
        let suffix = String(text[suffixStart...])
        if suffix.contains(where: \.isWhitespace) {
            return nil
        }

        return suffix
    }

    private var matchingTags: [String] {
        guard let query = activeTagQuery else { return [] }

        let candidates = availableTags.filter { !selectedSearchTags.contains($0) }
        guard !query.isEmpty else { return candidates }
        return candidates.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    private var hasSearchTokens: Bool {
        !selectedSearchTags.isEmpty || !(activeTagQuery?.isEmpty ?? true)
    }

    private var plainSearchKeyword: String {
        removeActiveTagQuery(from: searchText)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
                    VStack(alignment: .leading, spacing: 6) {
                        if hasSearchTokens {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(selectedSearchTags, id: \.self) { tag in
                                        SearchTagToken(text: tag) {
                                            removeSearchTag(tag)
                                        }
                                    }

                                    if let activeTagQuery {
                                        DraftSearchTagToken(text: activeTagQuery)
                                    }
                                }
                                .padding(.vertical, 1)
                            }
                        }

                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)

                            TextField("搜索标题，输入 % 按标签筛选", text: $searchText)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12))
                                .focused($isSearchFieldFocused)
                                .onSubmit {
                                    commitActiveTagIfNeeded()
                                }
                                .onChange(of: searchText) { _, _ in
                                    syncHighlightedTag()
                                }
                                .onKeyPress(.leftArrow) {
                                    guard isSearchFieldFocused, matchingTags.count > 1 else {
                                        return .ignored
                                    }
                                    moveHighlightedTag(step: -1)
                                    return .handled
                                }
                                .onKeyPress(.rightArrow) {
                                    guard isSearchFieldFocused, matchingTags.count > 1 else {
                                        return .ignored
                                    }
                                    moveHighlightedTag(step: 1)
                                    return .handled
                                }

                            Text("\(filteredTasks.count)条")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)

                            Button {
                                Task { await viewModel.refreshProjectAnalyses() }
                            } label: {
                                RefreshingIcon(
                                    systemName: "arrow.triangle.2.circlepath",
                                    isAnimating: viewModel.isRefreshingProjects
                                )
                                .font(.system(size: 11))
                                .foregroundStyle(.indigo)
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.isRefreshingProjects || !viewModel.refreshingProjectIds.isEmpty)
                            .help("刷新项目分析")

                            cleanupButton
                        }

                        if !matchingTags.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(matchingTags, id: \.self) { tag in
                                        Button {
                                            addSearchTag(tag)
                                        } label: {
                                            TagChip(text: tag)
                                        }
                                        .buttonStyle(.plain)
                                        .overlay {
                                            if highlightedTag == tag {
                                                RoundedRectangle(cornerRadius: 999)
                                                    .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
                                            }
                                        }
                                    }
                                }
                                .padding(.vertical, 1)
                            }
                        }
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
                                IdeaPoolTaskRow(
                                    task: task,
                                    isNew: viewModel.newlyAddedTaskIds.contains(task.id),
                                    isRefreshingProject: viewModel.isRefreshingProjects || viewModel.refreshingProjectIds.contains(task.id)
                                ) { priority in
                                    Task { await viewModel.promoteToMustDo(taskId: task.id, priority: priority) }
                                } onDelete: {
                                    Task { await viewModel.deleteTask(taskId: task.id) }
                                } onUpdate: { title, category, estimatedMinutes, note in
                                    Task {
                                        await viewModel.updateTask(
                                            taskId: task.id,
                                            title: title,
                                            category: category,
                                            estimatedMinutes: estimatedMinutes,
                                            note: note
                                        )
                                    }
                                } onRefreshProject: {
                                    Task { await viewModel.refreshProjectAnalyses(taskId: task.id) }
                                } onUpdateProjectState: { isProject in
                                    Task { await viewModel.updateProjectState(taskId: task.id, isProject: isProject) }
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                    }
                }
            }
            .frame(maxHeight: viewModel.isExpanded ? nil : 0, alignment: .top)
            .clipped()
            .opacity(viewModel.isExpanded ? 1 : 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.08))
        .cornerRadius(8)
    }

    private func removeActiveTagQuery(from text: String) -> String {
        guard let percentIndex = text.lastIndex(of: "%") else { return text }

        let prefix = text[..<percentIndex]
        if let lastPrefix = prefix.last, !lastPrefix.isWhitespace {
            return text
        }

        let suffixStart = text.index(after: percentIndex)
        let suffix = String(text[suffixStart...])
        if suffix.contains(where: \.isWhitespace) {
            return text
        }

        return String(prefix)
    }

    private func syncHighlightedTag() {
        if let highlightedTag, matchingTags.contains(highlightedTag) {
            return
        }
        self.highlightedTag = matchingTags.first
    }

    private func commitActiveTagIfNeeded() {
        guard let tag = highlightedTag ?? matchingTags.first else { return }
        addSearchTag(tag)
    }

    private func moveHighlightedTag(step: Int) {
        guard !matchingTags.isEmpty else { return }

        let currentIndex = highlightedTag.flatMap { matchingTags.firstIndex(of: $0) } ?? 0
        let nextIndex = (currentIndex + step + matchingTags.count) % matchingTags.count
        highlightedTag = matchingTags[nextIndex]
    }

    private func addSearchTag(_ tag: String) {
        guard !selectedSearchTags.contains(tag) else { return }
        selectedSearchTags.append(tag)

        let plainText = removeActiveTagQuery(from: searchText)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        searchText = plainText.isEmpty ? "" : plainText + " "
        highlightedTag = nil
        isSearchFieldFocused = true
    }

    private func removeSearchTag(_ tag: String) {
        selectedSearchTags.removeAll { $0 == tag }
        syncHighlightedTag()
    }

    // MARK: - 清理按钮

    private var cleanupButton: some View {
        Group {
            switch viewModel.cleanupState {
            case .idle:
                Button {
                    Task { await viewModel.fetchCleanupSuggestions() }
                } label: {
                    Image(systemName: "flask")
                        .font(.system(size: 11))
                        .foregroundStyle(.teal)
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
                    Image(systemName: "flask")
                        .font(.system(size: 11))
                        .foregroundStyle(.teal)
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

private struct SearchTagToken: View {
    let text: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            TagChip(text: text)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.trailing, 2)
    }
}

private struct DraftSearchTagToken: View {
    let text: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "tag.fill")
                .font(.system(size: 7, weight: .semibold))
            Text(text.isEmpty ? "输入标签..." : text)
                .font(.system(size: 9))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.accentColor.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 999)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(Color.accentColor.opacity(0.35))
        )
        .clipShape(Capsule())
        .foregroundStyle(Color.accentColor)
    }
}

struct IdeaPoolTaskRow: View {
    let task: TaskEntity
    var isNew: Bool = false
    var isRefreshingProject: Bool = false
    let onPromote: (TaskPriority) -> Void
    let onDelete: () -> Void
    let onUpdate: (_ title: String?, _ category: String?, _ estimatedMinutes: Int?, _ note: String?) -> Void
    let onRefreshProject: () -> Void
    let onUpdateProjectState: (Bool) -> Void

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

    private enum Field: Hashable {
        case title, minutes, note
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

                    if task.aiRecommended {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                    }

                    Menu {
                        Button(task.isProjectTask ? "设为普通想法" : "设为项目") {
                            onUpdateProjectState(!task.isProjectTask)
                        }
                    } label: {
                        if task.isProjectTask {
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
                    } else {
                        Label(task.estimatedMinutes.hourMinuteString, systemImage: "clock")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .onTapGesture { startEditingMinutes() }
                    }

                    Text(task.createdDate.relativeTimeString())
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                // AI 推荐理由
                if task.aiRecommended, let reason = task.recommendationReason {
                    TooltipText(text: "💡 \(reason)", tooltip: reason)
                }

                if task.isProjectTask {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            ProgressView(value: (task.projectProgress ?? 0) / 100)
                                .progressViewStyle(.linear)
                                .tint(.indigo)
                            Text("\(Int(task.projectProgress ?? 0))%")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                            Button(action: onRefreshProject) {
                                RefreshingIcon(
                                    systemName: "arrow.clockwise",
                                    isAnimating: isRefreshingProject
                                )
                                .font(.system(size: 10))
                                .foregroundStyle(.indigo)
                            }
                            .buttonStyle(.plain)
                            .disabled(isRefreshingProject)
                            .help("刷新项目进度")
                        }

                        if let summary = task.projectProgressSummary, !summary.isEmpty {
                            Text(summary)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
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
                if editingMinutes { commitMinutesEdit() }
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
        if editingMinutes {
            commitMinutesEdit()
        }
        draftTitle = task.title
        editingTitle = true
        focusedField = .title
        moveInsertionPointToEnd()
    }

    private func commitTitleEdit() {
        editingTitle = false
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != task.title else { return }
        onUpdate(trimmed, nil, nil, nil)
    }

    private func startEditingMinutes() {
        if editingTitle {
            commitTitleEdit()
        }
        if editingNote {
            commitNoteEdit()
        }
        draftMinutes = task.estimatedMinutes.hourMinuteString
        editingMinutes = true
        focusedField = .minutes
        moveInsertionPointToEnd()
    }

    private func commitMinutesEdit() {
        editingMinutes = false
        let trimmed = draftMinutes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let minutes = trimmed.parsedHourMinuteDuration, minutes != task.estimatedMinutes else { return }
        onUpdate(nil, nil, minutes, nil)
    }

    private func startEditingNote() {
        // 如果正在编辑标题，先提交标题
        if editingTitle {
            commitTitleEdit()
        }
        if editingMinutes {
            commitMinutesEdit()
        }
        draftNote = task.note ?? ""
        editingNote = true
        focusedField = .note
        moveInsertionPointToEnd()
    }

    private func commitNoteEdit() {
        editingNote = false
        let trimmed = draftNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != (task.note ?? "") {
            onUpdate(nil, nil, nil, trimmed)
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
                        onUpdate(nil, tag, nil, nil)
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

    private func moveInsertionPointToEnd(retryCount: Int = 3) {
        DispatchQueue.main.async {
            guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else {
                if retryCount > 0 {
                    moveInsertionPointToEnd(retryCount: retryCount - 1)
                }
                return
            }

            let endLocation = textView.string.count
            textView.setSelectedRange(NSRange(location: endLocation, length: 0))
        }
    }
}

private struct RefreshingIcon: View {
    let systemName: String
    let isAnimating: Bool

    var body: some View {
        TimelineView(.animation) { context in
            Image(systemName: systemName)
                .rotationEffect(.degrees(rotationAngle(at: context.date)))
        }
    }

    private func rotationAngle(at date: Date) -> Double {
        guard isAnimating else { return 0 }
        let cycleDuration = 0.9
        let progress = date.timeIntervalSinceReferenceDate.remainder(dividingBy: cycleDuration) / cycleDuration
        return progress * 360
    }
}
