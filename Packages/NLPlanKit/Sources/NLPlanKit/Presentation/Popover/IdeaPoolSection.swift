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
    @FocusState private var isSearchFieldFocused: Bool

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

    private var allItems: [IdeaPoolListItem] {
        let ideaItems = viewModel.ideas.map { IdeaPoolListItem.idea($0) }
        let projectItems = viewModel.projects.map { IdeaPoolListItem.project($0) }
        return ideaItems + projectItems
    }

    private var filteredItems: [IdeaPoolListItem] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasKeyword = !keyword.isEmpty
        let hasTags = !selectedSearchTags.isEmpty
        let matchedItems = (hasKeyword || hasTags) ? allItems.filter { item in
            let matchesKeyword = !hasKeyword || item.title.localizedCaseInsensitiveContains(keyword)
            let matchesTag = !hasTags || selectedSearchTags.contains(item.category)
            return matchesKeyword && matchesTag
        } : allItems
        return sortItems(matchedItems)
    }

    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            if allItems.isEmpty {
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

                            Text("\(filteredItems.count)条")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)

                            HoverIconButton(
                                icon: "arrow.triangle.2.circlepath",
                                iconSize: 11,
                                color: .indigo,
                                action: { Task { await viewModel.refreshProjectAnalyses() } }
                            )
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

                    if filteredItems.isEmpty && hasSearchTokens {
                        Text("未找到匹配的计划")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 16)
                    } else {
                        LazyVStack(spacing: 4) {
                            ForEach(filteredItems) { item in
                                switch item {
                                case .idea(let idea):
                                    IdeaPoolTaskRow(
                                        idea: idea,
                                        isNew: viewModel.newlyAddedIdeaIds.contains(idea.id),
                                        onTogglePin: {
                                            Task { await viewModel.togglePin(for: .idea(idea)) }
                                        }
                                    ) { priority in
                                        Task { await viewModel.promoteToMustDo(ideaId: idea.id, priority: priority) }
                                    } onDelete: {
                                        viewModel.requestDelete(ideaId: idea.id)
                                    } onUpdate: { title, category, estimatedMinutes, note, deadline in
                                        Task {
                                            await viewModel.updateIdea(
                                                ideaId: idea.id,
                                                title: title,
                                                category: category,
                                                estimatedMinutes: estimatedMinutes,
                                                note: note,
                                                deadline: deadline
                                            )
                                        }
                                    }
                                case .project(let project):
                                    ProjectPoolRow(
                                        project: project,
                                        isRefreshing: viewModel.isRefreshingProjects || viewModel.refreshingProjectIds.contains(project.id),
                                        onTogglePin: {
                                            Task { await viewModel.togglePin(for: .project(project)) }
                                        }
                                    ) { priority in
                                        Task { await viewModel.promoteProjectToMustDo(projectId: project.id, priority: priority) }
                                    } onDelete: {
                                        viewModel.requestDeleteProject(projectId: project.id)
                                    } onRefresh: {
                                        Task { await viewModel.refreshProjectAnalyses(projectId: project.id) }
                                    } onOpenDetail: {
                                        appState.currentPage = .projectDetail(project.id)
                                    } onUpdate: { title, category, deadline in
                                        Task {
                                            await viewModel.updateProject(
                                                projectId: project.id,
                                                title: title,
                                                category: category,
                                                deadline: deadline
                                            )
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Search helpers

    private func syncHighlightedCandidateTag() {
        guard isCandidateTagNavigationEnabled else { highlightedCandidateTag = nil; return }
        if let highlightedCandidateTag, candidateTags.contains(highlightedCandidateTag) { return }
        self.highlightedCandidateTag = candidateTags.first
    }

    private func sortItems(_ items: [IdeaPoolListItem]) -> [IdeaPoolListItem] {
        items.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }
            if lhs.isPinned, rhs.isPinned {
                let lhsPinnedAt = lhs.pinnedAt ?? .distantPast
                let rhsPinnedAt = rhs.pinnedAt ?? .distantPast
                if lhsPinnedAt != rhsPinnedAt {
                    return lhsPinnedAt > rhsPinnedAt
                }
            }
            if lhs.createdDate != rhs.createdDate {
                return lhs.createdDate > rhs.createdDate
            }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
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
        let plainText = removeActiveTagQuery(from: searchText).trimmingCharacters(in: .whitespacesAndNewlines)
        searchText = plainText.isEmpty ? "" : plainText + " "
        highlightedCandidateTag = nil
        isSearchFieldFocused = true
    }

    private func removeSearchTag(_ tag: String) {
        guard let idx = selectedSearchTags.firstIndex(of: tag) else { return }
        selectedSearchTags.remove(at: idx)
        if let hIdx = highlightedSelectedTagIndex {
            if selectedSearchTags.isEmpty { highlightedSelectedTagIndex = nil }
            else if hIdx >= selectedSearchTags.count { highlightedSelectedTagIndex = selectedSearchTags.count - 1 }
            else if hIdx > idx { highlightedSelectedTagIndex = hIdx - 1 }
        }
        syncHighlightedCandidateTag()
        if selectedSearchTags.isEmpty { clearSelectedTagHighlight(focusSearch: true) }
    }

    @discardableResult
    private func removeHighlightedSearchTag() -> Bool {
        guard let idx = highlightedSelectedTagIndex, selectedSearchTags.indices.contains(idx) else { return false }
        removeSearchTag(selectedSearchTags[idx])
        if selectedSearchTags.isEmpty { clearSelectedTagHighlight(focusSearch: true) }
        else { highlightedSelectedTagIndex = min(idx, selectedSearchTags.count - 1) }
        return true
    }

    private func clearSelectedTagHighlight(focusSearch: Bool) { highlightedSelectedTagIndex = nil; if focusSearch { isSearchFieldFocused = true } }
    private func deactivateCandidateTagNavigation() { isCandidateTagNavigationEnabled = false; highlightedCandidateTag = nil; isSearchFieldFocused = true }
    private func activateCandidateTagNavigationIfNeeded() { guard !candidateTags.isEmpty else { return }; isCandidateTagNavigationEnabled = true; syncHighlightedCandidateTag() }
    private func focusSearchFieldOnFirstAppear() { guard !didAutoFocusSearchField else { return }; didAutoFocusSearchField = true; DispatchQueue.main.async { isSearchFieldFocused = true } }

    @discardableResult
    private func handleSelectedTagKeyCommand(_ command: SearchTagKeyCommand) -> Bool {
        switch command {
        case .left: guard let idx = highlightedSelectedTagIndex else { return false }; highlightedSelectedTagIndex = max(0, idx - 1); return true
        case .right: guard let idx = highlightedSelectedTagIndex else { return false }; highlightedSelectedTagIndex = min(selectedSearchTags.count - 1, idx + 1); return true
        case .up: clearSelectedTagHighlight(focusSearch: true); return true
        case .down: clearSelectedTagHighlight(focusSearch: true); return true
        case .delete: return removeHighlightedSearchTag()
        case .blockTextInput: return true
        }
    }

    private func removeActiveTagQuery(from text: String) -> String {
        guard let percentIndex = text.lastIndex(of: "%") else { return text }
        let prefix = text[..<percentIndex]
        if let lastPrefix = prefix.last, !lastPrefix.isWhitespace { return text }
        let suffixStart = text.index(after: percentIndex)
        let suffix = String(text[suffixStart...])
        if suffix.contains(where: \.isWhitespace) { return text }
        return String(prefix)
    }

    // MARK: - 清理按钮

    private var cleanupButton: some View {
        Group {
            switch viewModel.cleanupState {
            case .idle:
                HoverIconButton(icon: "flask", iconSize: 11, color: .teal) {
                    Task { await viewModel.fetchCleanupSuggestions() }
                }
                .help("AI 清理")

            case .loading:
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 16, height: 16)

            case .loaded:
                HoverIconButton(icon: "flask", iconSize: 11, color: .teal) {
                    appState.currentPage = .cleanupDetail
                }
                .help("查看清理建议")

            case .error:
                HoverIconButton(icon: "exclamationmark.triangle", iconSize: 11, color: .red) {
                    Task { await viewModel.fetchCleanupSuggestions() }
                }
                .help("重试 AI 清理")
            }
        }
    }
}
