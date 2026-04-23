import AppKit
import SwiftUI

/// 想法池区域
struct IdeaPoolSection: View {
    @Bindable var viewModel: IdeaPoolViewModel
    @State private var searchText: String = ""
    @State private var selectedSearchTags: [String] = []
    @State private var highlightedCandidateTag: String?
    @State private var isCandidateTagNavigationEnabled = false
    @State private var highlightedSelectedTagIndex: Int?
    @State private var didAutoFocusSearchField = false
    @State private var selectedProjectTask: TaskEntity?
    @State private var linkedMustDoTasks: [TaskEntity] = []
    @State private var isLoadingProjectDetail = false
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

    private var candidateTags: [String] {
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
        ZStack {
            VStack(spacing: 0) {
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
                                    ForEach(Array(selectedSearchTags.enumerated()), id: \.element) { index, tag in
                                        SearchTagToken(
                                            text: tag,
                                            isHighlighted: highlightedSelectedTagIndex == index
                                        ) {
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
                                    highlightedSelectedTagIndex = nil
                                    if activeTagQuery != nil {
                                        isCandidateTagNavigationEnabled = true
                                    } else {
                                        isCandidateTagNavigationEnabled = false
                                        highlightedCandidateTag = nil
                                    }
                                    syncHighlightedCandidateTag()
                                }
                                .onKeyPress(.upArrow) {
                                    if isCandidateTagNavigationEnabled, !candidateTags.isEmpty {
                                        deactivateCandidateTagNavigation()
                                        return .handled
                                    }
                                    guard highlightedSelectedTagIndex == nil, !selectedSearchTags.isEmpty else { return .ignored }
                                    highlightedSelectedTagIndex = 0
                                    isSearchFieldFocused = false
                                    return .handled
                                }
                                .onKeyPress(.downArrow) {
                                    if highlightedSelectedTagIndex != nil {
                                        clearSelectedTagHighlight(focusSearch: true)
                                        return .handled
                                    }
                                    if !isCandidateTagNavigationEnabled, !candidateTags.isEmpty {
                                        activateCandidateTagNavigationIfNeeded()
                                        return .handled
                                    }
                                    return .ignored
                                }
                                .onKeyPress(.leftArrow) {
                                    if let idx = highlightedSelectedTagIndex {
                                        highlightedSelectedTagIndex = max(0, idx - 1)
                                        return .handled
                                    }
                                    guard isCandidateTagNavigationEnabled, candidateTags.count > 1 else { return .ignored }
                                    moveHighlightedCandidateTag(step: -1)
                                    return .handled
                                }
                                .onKeyPress(.rightArrow) {
                                    if let idx = highlightedSelectedTagIndex {
                                        highlightedSelectedTagIndex = min(selectedSearchTags.count - 1, idx + 1)
                                        return .handled
                                    }
                                    guard isCandidateTagNavigationEnabled, candidateTags.count > 1 else { return .ignored }
                                    moveHighlightedCandidateTag(step: 1)
                                    return .handled
                                }
                                .onKeyPress(.escape) {
                                    if isCandidateTagNavigationEnabled, !candidateTags.isEmpty {
                                        deactivateCandidateTagNavigation()
                                        return .handled
                                    }
                                    if highlightedSelectedTagIndex != nil {
                                        clearSelectedTagHighlight(focusSearch: true)
                                        return .handled
                                    }
                                    return .ignored
                                }
                                .onKeyPress(.delete) {
                                    guard removeHighlightedSearchTag() else { return .ignored }
                                    return .handled
                                }
                                .background {
                                    SearchTagKeyMonitor(
                                        isEnabled: highlightedSelectedTagIndex != nil
                                    ) { command in
                                        handleSelectedTagKeyCommand(command)
                                    }
                                    .frame(width: 0, height: 0)
                                }
                                .onTapGesture {
                                    clearSelectedTagHighlight(focusSearch: true)
                                }
                                .onAppear {
                                    focusSearchFieldOnFirstAppear()
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

                        if !candidateTags.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(candidateTags, id: \.self) { tag in
                                        Button {
                                            addSearchTag(tag)
                                        } label: {
                                            TagChip(text: tag)
                                        }
                                        .buttonStyle(.plain)
                                        .overlay {
                                            if isCandidateTagNavigationEnabled, highlightedCandidateTag == tag {
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
                                } onOpenProject: {
                                    openProjectDetail(task)
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let selectedProjectTask {
                ProjectDetailOverlay(
                    project: selectedProjectTask,
                    linkedTasks: linkedMustDoTasks,
                    isLoading: isLoadingProjectDetail,
                    onAddNote: { content in
                        Task {
                            await viewModel.addProjectNote(taskId: selectedProjectTask.id, content: content)
                        }
                    },
                    onUpdateNote: { noteId, content in
                        Task {
                            await viewModel.updateProjectNote(noteId: noteId, content: content)
                        }
                    }
                ) {
                    closeProjectDetail()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: selectedProjectTask?.id)
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

    private func syncHighlightedCandidateTag() {
        guard isCandidateTagNavigationEnabled else {
            highlightedCandidateTag = nil
            return
        }
        if let highlightedCandidateTag, candidateTags.contains(highlightedCandidateTag) {
            return
        }
        self.highlightedCandidateTag = candidateTags.first
    }

    private func commitActiveTagIfNeeded() {
        guard let tag = highlightedCandidateTag ?? candidateTags.first else { return }
        addSearchTag(tag)
    }

    private func moveHighlightedCandidateTag(step: Int) {
        guard !candidateTags.isEmpty else { return }

        let currentIndex = highlightedCandidateTag.flatMap { candidateTags.firstIndex(of: $0) } ?? 0
        let nextIndex = (currentIndex + step + candidateTags.count) % candidateTags.count
        highlightedCandidateTag = candidateTags[nextIndex]
    }

    private func addSearchTag(_ tag: String) {
        guard !selectedSearchTags.contains(tag) else { return }
        selectedSearchTags.append(tag)
        highlightedSelectedTagIndex = nil

        let plainText = removeActiveTagQuery(from: searchText)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        searchText = plainText.isEmpty ? "" : plainText + " "
        highlightedCandidateTag = nil
        isSearchFieldFocused = true
    }

    private func removeSearchTag(_ tag: String) {
        guard let idx = selectedSearchTags.firstIndex(of: tag) else { return }
        selectedSearchTags.remove(at: idx)
        if let hIdx = highlightedSelectedTagIndex {
            if selectedSearchTags.isEmpty {
                highlightedSelectedTagIndex = nil
            } else if hIdx >= selectedSearchTags.count {
                highlightedSelectedTagIndex = selectedSearchTags.count - 1
            } else if hIdx > idx {
                highlightedSelectedTagIndex = hIdx - 1
            }
        }
        syncHighlightedCandidateTag()
        if selectedSearchTags.isEmpty {
            clearSelectedTagHighlight(focusSearch: true)
        }
    }

    @discardableResult
    private func removeHighlightedSearchTag() -> Bool {
        guard let idx = highlightedSelectedTagIndex,
              selectedSearchTags.indices.contains(idx) else { return false }

        removeSearchTag(selectedSearchTags[idx])
        if selectedSearchTags.isEmpty {
            clearSelectedTagHighlight(focusSearch: true)
        } else {
            highlightedSelectedTagIndex = min(idx, selectedSearchTags.count - 1)
        }
        return true
    }

    private func clearSelectedTagHighlight(focusSearch: Bool) {
        highlightedSelectedTagIndex = nil
        if focusSearch {
            isSearchFieldFocused = true
        }
    }

    private func deactivateCandidateTagNavigation() {
        isCandidateTagNavigationEnabled = false
        highlightedCandidateTag = nil
        isSearchFieldFocused = true
    }

    private func activateCandidateTagNavigationIfNeeded() {
        guard !candidateTags.isEmpty else { return }
        isCandidateTagNavigationEnabled = true
        syncHighlightedCandidateTag()
    }

    private func focusSearchFieldOnFirstAppear() {
        guard !didAutoFocusSearchField else { return }
        didAutoFocusSearchField = true
        DispatchQueue.main.async {
            isSearchFieldFocused = true
        }
    }

    @discardableResult
    private func handleSelectedTagKeyCommand(_ command: SearchTagKeyCommand) -> Bool {
        switch command {
        case .left:
            guard let idx = highlightedSelectedTagIndex else { return false }
            highlightedSelectedTagIndex = max(0, idx - 1)
            return true

        case .right:
            guard let idx = highlightedSelectedTagIndex else { return false }
            highlightedSelectedTagIndex = min(selectedSearchTags.count - 1, idx + 1)
            return true

        case .up:
            clearSelectedTagHighlight(focusSearch: true)
            return true

        case .down:
            clearSelectedTagHighlight(focusSearch: true)
            return true

        case .delete:
            return removeHighlightedSearchTag()

        case .blockTextInput:
            return true
        }
    }

    private func openProjectDetail(_ task: TaskEntity) {
        guard task.isProjectTask else { return }
        selectedProjectTask = task
        linkedMustDoTasks = []
        isLoadingProjectDetail = true
        isSearchFieldFocused = false

        Task {
            let tasks = await viewModel.fetchLinkedMustDoTasks(sourceIdeaId: task.id)
            guard selectedProjectTask?.id == task.id else { return }
            linkedMustDoTasks = tasks
            isLoadingProjectDetail = false
        }
    }

    private func closeProjectDetail() {
        selectedProjectTask = nil
        linkedMustDoTasks = []
        isLoadingProjectDetail = false
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
    var isHighlighted: Bool = false
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            TagChip(text: text)

            if !isHighlighted {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.trailing, 2)
        .overlay {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 999)
                    .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
            }
        }
    }
}

private struct ProjectDetailOverlay: View {
    let project: TaskEntity
    let linkedTasks: [TaskEntity]
    let isLoading: Bool
    let onAddNote: (String) -> Void
    let onUpdateNote: (UUID, String) -> Void
    let onClose: () -> Void

    @State private var newNoteText: String = ""

    private var projectNotes: [ProjectNoteEntity] {
        project.projectNotes.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    projectSummaryCard
                    progressCard
                    linkedTasksCard
                    noteCard
                }
                .padding(12)
            }
            .scrollIndicators(.never)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 4)
        .padding(8)
    }

    private var header: some View {
        HStack(spacing: 8) {
            BackButton(action: onClose)
            .help("返回想法池")

            Image(systemName: "folder.fill")
                .font(.system(size: 12))
                .foregroundStyle(.indigo)

            Text("项目详情")
                .font(.system(size: 13, weight: .semibold))

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var projectSummaryCard: some View {
        DetailSectionCard(
            title: "项目信息",
            systemImage: "lightbulb.fill",
            tint: .yellow,
            background: Color.yellow.opacity(0.08),
            border: Color.yellow.opacity(0.22)
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text(project.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(3)

                HStack(spacing: 8) {
                    TagChip(text: project.category)

                    Text(project.createdDate.shortDateTimeString)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                if project.attempted {
                    Text("已尝试")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
        }
    }

    private var progressCard: some View {
        DetailSectionCard(
            title: "进度",
            systemImage: "chart.line.uptrend.xyaxis",
            tint: .indigo,
            background: Color.indigo.opacity(0.08),
            border: Color.indigo.opacity(0.22)
        ) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ProgressView(value: (project.projectProgress ?? 0) / 100)
                        .progressViewStyle(.linear)
                        .tint(.indigo)

                    Text("\(Int(project.projectProgress ?? 0))%")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.indigo)
                }

                if let summary = project.projectProgressSummary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("暂无进度分析")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                if let updatedAt = project.projectProgressUpdatedAt {
                    Text("更新于 \(updatedAt.shortDateTimeString)")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var linkedTasksCard: some View {
        DetailSectionCard(
            title: "推进任务清单",
            systemImage: "link",
            tint: .blue,
            background: Color.blue.opacity(0.08),
            border: Color.blue.opacity(0.22)
        ) {
            VStack(alignment: .leading, spacing: 8) {
                if isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("加载中")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if linkedTasks.isEmpty {
                    Text("暂无推进任务")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(linkedTasks, id: \.id) { task in
                        ProjectLinkedTaskRow(task: task)
                    }
                }
            }
        }
    }

    private var noteCard: some View {
        DetailSectionCard(
            title: "项目备注记录",
            systemImage: "note.text",
            tint: .mint,
            background: Color.mint.opacity(0.08),
            border: Color.mint.opacity(0.24)
        ) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 6) {
                    TextField("新增备注...", text: $newNoteText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 5)
                        .background(Color(nsColor: .windowBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .submitLabel(.done)
                        .onSubmit {
                            submitNewNote()
                        }

                    Button("添加") { submitNewNote() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .disabled(newNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if projectNotes.isEmpty {
                    Text("暂无备注记录")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(projectNotes, id: \.id) { note in
                        ProjectNoteRow(note: note) { updatedText in
                            onUpdateNote(note.id, updatedText)
                        }
                    }
                }
            }
        }
    }

    private func submitNewNote() {
        let trimmed = newNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onAddNote(trimmed)
        newNoteText = ""
    }
}

private struct DetailSectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    let background: Color
    let border: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)

            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ProjectLinkedTaskRow: View {
    let task: TaskEntity

    private var statusColor: Color {
        switch task.taskStatus {
        case .done: return .green
        case .running: return .blue
        case .paused: return .orange
        case .pending: return .secondary
        }
    }

    private var priorityColor: Color {
        switch task.taskPriority {
        case .high: return .red
        case .medium: return .orange
        case .low: return .blue
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: task.taskStatus.iconName)
                    .font(.system(size: 12))
                    .foregroundStyle(statusColor)

                Text(task.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(2)

                Spacer(minLength: 0)

                statusBadge
            }

            HStack(spacing: 8) {
                Label(task.taskPriority.displayName, systemImage: task.taskPriority.iconName)
                    .foregroundStyle(priorityColor)

                Label(task.estimatedMinutes.hourMinuteString, systemImage: "clock")

                if task.totalElapsedSeconds > 0 {
                    Label((task.totalElapsedSeconds / 60).hourMinuteString, systemImage: "timer")
                }
            }
            .font(.system(size: 9))
            .foregroundStyle(.secondary)

            Text("创建于 \(task.createdDate.shortDateTimeString)")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .padding(8)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private var statusBadge: some View {
        Text(task.taskStatus.displayName)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusColor.opacity(0.1))
            .clipShape(Capsule())
    }
}

private struct ProjectNoteRow: View {
    let note: ProjectNoteEntity
    let onUpdate: (String) -> Void

    @State private var isEditing = false
    @State private var draftText = ""

    private var createdText: String {
        note.createdAt.relativeTimeString()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isEditing {
                TextField("备注内容", text: $draftText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(2...4)
                    .font(.system(size: 11))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Text(note.content)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Text(createdText)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 0)

                if isEditing {
                    Button("取消") {
                        isEditing = false
                        draftText = note.content
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                    Button("保存") {
                        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty, trimmed != note.content else {
                            isEditing = false
                            draftText = note.content
                            return
                        }
                        onUpdate(trimmed)
                        isEditing = false
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else {
                    Button("编辑") {
                        draftText = note.content
                        isEditing = true
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .onAppear {
            draftText = note.content
        }
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

private enum SearchTagKeyCommand {
    case left
    case right
    case up
    case down
    case delete
    case blockTextInput
}

private struct SearchTagKeyMonitor: NSViewRepresentable {
    var isEnabled: Bool
    let onCommand: (SearchTagKeyCommand) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isEnabled: isEnabled, onCommand: onCommand)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.installMonitor()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onCommand = onCommand
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    final class Coordinator {
        var isEnabled: Bool
        var onCommand: (SearchTagKeyCommand) -> Bool
        private var monitor: Any?

        init(isEnabled: Bool, onCommand: @escaping (SearchTagKeyCommand) -> Bool) {
            self.isEnabled = isEnabled
            self.onCommand = onCommand
        }

        deinit {
            removeMonitor()
        }

        func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.isEnabled, let command = event.searchTagKeyCommand else { return event }
                return self.onCommand(command) ? nil : event
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}

private extension NSEvent {
    var searchTagKeyCommand: SearchTagKeyCommand? {
        let passthroughModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        guard modifierFlags.intersection(passthroughModifiers).isEmpty else { return nil }

        switch keyCode {
        case 51, 117:
            return .delete
        case 123:
            return .left
        case 124:
            return .right
        case 125:
            return .down
        case 126:
            return .up
        default:
            return charactersIgnoringModifiers?.isEmpty == false ? .blockTextInput : nil
        }
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

                    if task.isProjectTask {
                        EmptyView()
                    } else if editingMinutes {
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

            Spacer(minLength: 12)

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
        .background {
            rowBackground
                .contentShape(Rectangle())
                .onTapGesture {
                    focusedField = nil
                    if task.isProjectTask {
                        onOpenProject()
                    }
                }
        }
        .cornerRadius(6)
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

    private var rowBackground: Color {
        flashCount % 2 == 1 ? Color.accentColor.opacity(0.15) : Color(nsColor: .textBackgroundColor)
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
        if isAnimating {
            TimelineView(.animation) { context in
                Image(systemName: systemName)
                    .rotationEffect(.degrees(angle(at: context.date)))
            }
        } else {
            Image(systemName: systemName)
        }
    }

    private func angle(at date: Date) -> Double {
        (date.timeIntervalSinceReferenceDate.remainder(dividingBy: 0.9) / 0.9) * 360
    }
}
