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
    @FocusState private var isSearchFieldFocused: Bool

    private var filteredIdeas: [IdeaEntity] {
        let keyword = plainSearchKeyword
        let hasKeyword = !keyword.isEmpty
        let hasTags = !selectedSearchTags.isEmpty
        guard hasKeyword || hasTags else { return viewModel.ideas }

        return viewModel.ideas.filter { idea in
            let matchesKeyword = !hasKeyword || idea.title.localizedCaseInsensitiveContains(keyword)
            let matchesTag = !hasTags || selectedSearchTags.contains(idea.category)
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
            if viewModel.ideas.isEmpty {
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

                            Text("\(filteredIdeas.count)条")
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

                    if filteredIdeas.isEmpty {
                        Text("未找到匹配的计划")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 16)
                    } else {
                        LazyVStack(spacing: 4) {
                            ForEach(filteredIdeas, id: \.id) { idea in
                                IdeaPoolTaskRow(
                                    idea: idea,
                                    isNew: viewModel.newlyAddedIdeaIds.contains(idea.id),
                                    isRefreshingProject: viewModel.isRefreshingProjects || viewModel.refreshingProjectIds.contains(idea.id)
                                ) { priority in
                                    Task { await viewModel.promoteToMustDo(ideaId: idea.id, priority: priority) }
                                } onDelete: {
                                    Task { await viewModel.deleteIdea(ideaId: idea.id) }
                                } onUpdate: { title, category, estimatedMinutes, note in
                                    Task {
                                        await viewModel.updateIdea(
                                            ideaId: idea.id,
                                            title: title,
                                            category: category,
                                            estimatedMinutes: estimatedMinutes,
                                            note: note
                                        )
                                    }
                                } onRefreshProject: {
                                    Task { await viewModel.refreshProjectAnalyses(ideaId: idea.id) }
                                } onUpdateProjectState: { isProject in
                                    Task { await viewModel.updateProjectState(ideaId: idea.id, isProject: isProject) }
                                } onOpenProject: {
                                    appState.currentPage = .projectDetail(idea.id)
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
    }

    // MARK: - Search helpers (unchanged logic)

    private func removeActiveTagQuery(from text: String) -> String {
        guard let percentIndex = text.lastIndex(of: "%") else { return text }
        let prefix = text[..<percentIndex]
        if let lastPrefix = prefix.last, !lastPrefix.isWhitespace { return text }
        let suffixStart = text.index(after: percentIndex)
        let suffix = String(text[suffixStart...])
        if suffix.contains(where: \.isWhitespace) { return text }
        return String(prefix)
    }

    private func syncHighlightedCandidateTag() {
        guard isCandidateTagNavigationEnabled else { highlightedCandidateTag = nil; return }
        if let highlightedCandidateTag, candidateTags.contains(highlightedCandidateTag) { return }
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


// MARK: - IdeaPoolTaskRow (now uses IdeaEntity)

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
                    if idea.attempted { Text("已尝试").font(.system(size: 9)).foregroundStyle(.orange).padding(.horizontal, 4).padding(.vertical, 1).background(Color.orange.opacity(0.15)).cornerRadius(3) }
                    if isInProgress { Text("进行中").font(.system(size: 9, weight: .medium)).foregroundStyle(.green).padding(.horizontal, 4).padding(.vertical, 1).background(Color.green.opacity(0.14)).cornerRadius(3) }
                }
                HStack(spacing: 8) {
                    Button { showingCategoryMenu.toggle() } label: { TagChip(text: idea.category) }.buttonStyle(.plain)
                        .popover(isPresented: $showingCategoryMenu, attachmentAnchor: .point(.bottom), arrowEdge: .top) { categoryMenu }
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
                }
                if idea.aiRecommended, let reason = idea.recommendationReason { TooltipText(text: "💡 \(reason)", tooltip: reason) }
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

    private func startEditingTitle() { if editingNote { commitNoteEdit() }; if editingMinutes { commitMinutesEdit() }; draftTitle = idea.title; editingTitle = true; focusedField = .title; moveInsertionPointToEnd() }
    private func commitTitleEdit() { editingTitle = false; let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines); guard !trimmed.isEmpty, trimmed != idea.title else { return }; onUpdate(trimmed, nil, nil, nil) }
    private func startEditingMinutes() { if editingTitle { commitTitleEdit() }; if editingNote { commitNoteEdit() }; draftMinutes = (idea.estimatedMinutes ?? 30).hourMinuteString; editingMinutes = true; focusedField = .minutes; moveInsertionPointToEnd() }
    private func commitMinutesEdit() { editingMinutes = false; let trimmed = draftMinutes.trimmingCharacters(in: .whitespacesAndNewlines); guard let minutes = trimmed.parsedHourMinuteDuration, minutes != idea.estimatedMinutes else { return }; onUpdate(nil, nil, minutes, nil) }
    private func startEditingNote() { if editingTitle { commitTitleEdit() }; if editingMinutes { commitMinutesEdit() }; draftNote = idea.note ?? ""; editingNote = true; focusedField = .note; moveInsertionPointToEnd() }
    private func commitNoteEdit() { editingNote = false; let trimmed = draftNote.trimmingCharacters(in: .whitespacesAndNewlines); if trimmed != (idea.note ?? "") { onUpdate(nil, nil, nil, trimmed) } }

    private var availableTags: [String] { UserDefaults.standard.stringArray(forKey: AppConstants.tagsKey) ?? AppConstants.defaultTags }
    private var categoryMenu: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(availableTags, id: \.self) { tag in
                Button { showingCategoryMenu = false; if tag != idea.category { onUpdate(nil, tag, nil, nil) } } label: {
                    HStack(spacing: 6) {
                        if tag == idea.category { Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.accentColor) }
                        else { Color.clear.frame(width: 10, height: 10) }
                        TagChip(text: tag); Spacer(minLength: 0)
                    }.padding(.horizontal, 8).padding(.vertical, 6).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }.padding(6).frame(width: 180)
    }

    private func moveInsertionPointToEnd(retryCount: Int = 3) {
        DispatchQueue.main.async {
            guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { if retryCount > 0 { moveInsertionPointToEnd(retryCount: retryCount - 1) }; return }
            let endLocation = textView.string.count
            textView.setSelectedRange(NSRange(location: endLocation, length: 0))
        }
    }
}

// MARK: - Shared small views

private struct SearchTagToken: View {
    let text: String; var isHighlighted: Bool = false; let onRemove: () -> Void
    var body: some View {
        HStack(spacing: 4) {
            TagChip(text: text)
            if !isHighlighted { Button(action: onRemove) { Image(systemName: "xmark.circle.fill").font(.system(size: 10)).foregroundStyle(.secondary) }.buttonStyle(.plain) }
        }.padding(.trailing, 2).overlay { if isHighlighted { RoundedRectangle(cornerRadius: 999).stroke(Color.accentColor.opacity(0.35), lineWidth: 1) } }
    }
}

private struct DraftSearchTagToken: View {
    let text: String
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "tag.fill").font(.system(size: 7, weight: .semibold))
            Text(text.isEmpty ? "输入标签..." : text).font(.system(size: 9))
        }.padding(.horizontal, 6).padding(.vertical, 3).background(Color.accentColor.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 999).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3])).foregroundStyle(Color.accentColor.opacity(0.35)))
        .clipShape(Capsule()).foregroundStyle(Color.accentColor)
    }
}

private enum SearchTagKeyCommand { case left, right, up, down, delete, blockTextInput }

private struct SearchTagKeyMonitor: NSViewRepresentable {
    var isEnabled: Bool; let onCommand: (SearchTagKeyCommand) -> Bool
    func makeCoordinator() -> Coordinator { Coordinator(isEnabled: isEnabled, onCommand: onCommand) }
    func makeNSView(context: Context) -> NSView { let view = NSView(frame: .zero); context.coordinator.installMonitor(); return view }
    func updateNSView(_ nsView: NSView, context: Context) { context.coordinator.isEnabled = isEnabled; context.coordinator.onCommand = onCommand }
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.removeMonitor() }
    final class Coordinator {
        var isEnabled: Bool; var onCommand: (SearchTagKeyCommand) -> Bool; private var monitor: Any?
        init(isEnabled: Bool, onCommand: @escaping (SearchTagKeyCommand) -> Bool) { self.isEnabled = isEnabled; self.onCommand = onCommand }
        deinit { removeMonitor() }
        func installMonitor() { guard monitor == nil else { return }; monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in guard let self, self.isEnabled, let command = event.searchTagKeyCommand else { return event }; return self.onCommand(command) ? nil : event } }
        func removeMonitor() { if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil } }
    }
}

private extension NSEvent {
    var searchTagKeyCommand: SearchTagKeyCommand? {
        let passthroughModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        guard modifierFlags.intersection(passthroughModifiers).isEmpty else { return nil }
        switch keyCode {
        case 51, 117: return .delete; case 123: return .left; case 124: return .right; case 125: return .down; case 126: return .up
        default: return charactersIgnoringModifiers?.isEmpty == false ? .blockTextInput : nil
        }
    }
}

private struct RefreshingIcon: View {
    let systemName: String; let isAnimating: Bool
    var body: some View {
        if isAnimating { TimelineView(.animation) { context in Image(systemName: systemName).rotationEffect(.degrees(angle(at: context.date))) } }
        else { Image(systemName: systemName) }
    }
    private func angle(at date: Date) -> Double { (date.timeIntervalSinceReferenceDate.remainder(dividingBy: 0.9) / 0.9) * 360 }
}
