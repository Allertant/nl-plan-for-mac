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

            if viewModel.isExpanded {
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
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.08))
        .cornerRadius(8)
    }
}

/// 想法池任务卡片
struct IdeaPoolTaskRow: View {
    let task: TaskEntity
    var isNew: Bool = false
    let onPromote: (TaskPriority) -> Void
    let onDelete: () -> Void

    @State private var flashCount = 0
    @State private var showDeleteConfirm = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(task.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(2)

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

                HStack(spacing: 8) {
                    Label(task.category, systemImage: "tag")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    Label("\(task.estimatedMinutes)分钟", systemImage: "clock")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    Text(task.createdDate.dateString)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                if task.aiRecommended, let reason = task.recommendationReason {
                    TooltipText(text: "💡 \(reason)", tooltip: reason)
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
}
