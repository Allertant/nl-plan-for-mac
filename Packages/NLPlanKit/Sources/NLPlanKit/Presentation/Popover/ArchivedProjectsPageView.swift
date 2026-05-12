import SwiftUI

/// 归档/已完成项目查看页
struct ArchivedProjectsPageView: View {
    @Environment(AppState.self) private var appState
    @Bindable var viewModel: IdeaPoolViewModel
    let onBack: () -> Void

    @State private var selectedSegment = 0
    @State private var pendingRestoreProject: ProjectEntity?

    private var currentProjects: [ProjectEntity] {
        selectedSegment == 0 ? viewModel.archivedProjects : viewModel.completedProjects
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            segmentControl
            Divider()
            projectList
        }
        .frame(width: 360, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            if let project = pendingRestoreProject {
                ConfirmActionPage(
                    icon: "arrow.uturn.backward.circle",
                    iconTint: .indigo,
                    title: project.title,
                    message: "确认恢复该项目为进行中？",
                    confirmLabel: "确认恢复",
                    onCancel: { pendingRestoreProject = nil },
                    onConfirm: {
                        Task {
                            await viewModel.updateProjectStatus(
                                projectId: project.id,
                                status: .active
                            )
                            await viewModel.fetchArchivedProjects()
                            pendingRestoreProject = nil
                        }
                    }
                )
                .background(.ultraThinMaterial)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            BackButton(action: onBack)

            Image(systemName: "archivebox.fill")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))

            Text("项目归档")
                .font(.system(size: 13, weight: .semibold))

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Segment Control

    private var segmentControl: some View {
        HStack(spacing: 0) {
            segmentButton(title: "已归档", count: viewModel.archivedProjects.count, tag: 0)
            segmentButton(title: "已完成", count: viewModel.completedProjects.count, tag: 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func segmentButton(title: String, count: Int, tag: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedSegment = tag
            }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: selectedSegment == tag ? .semibold : .regular))
                    .foregroundStyle(selectedSegment == tag ? .primary : .secondary)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(selectedSegment == tag ? Color.accentColor : Color.secondary.opacity(0.5))
                        .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(selectedSegment == tag ? Color.accentColor.opacity(0.1) : .clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Project List

    private var projectList: some View {
        ScrollView {
            if currentProjects.isEmpty {
                emptyView
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(currentProjects, id: \.id) { project in
                        ArchivedProjectCard(
                            project: project,
                            onRestore: { pendingRestoreProject = project },
                            onOpenDetail: {
                                appState.returnPage = .archivedProjects
                                appState.currentPage = .projectDetail(project.id)
                            }
                        )
                    }
                }
                .padding(12)
            }
        }
        .frame(minHeight: 400, alignment: .top)
        .scrollIndicators(.automatic)
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: selectedSegment == 0 ? "archivebox" : "checkmark.circle")
                .font(.system(size: 28))
                .foregroundStyle(.secondary.opacity(0.5))
            Text(selectedSegment == 0 ? "暂无归档项目" : "暂无已完成项目")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
}

// MARK: - Archived Project Card

private struct ArchivedProjectCard: View {
    let project: ProjectEntity
    let onRestore: () -> Void
    let onOpenDetail: () -> Void

    @State private var isHovered = false

    private var statusText: String {
        if let status = ProjectStatus(rawValue: project.status) {
            return status.displayName
        }
        return ""
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(project.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(project.category)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    Text("·")
                        .foregroundStyle(.secondary)

                    Text(statusText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(action: onOpenDetail) {
                Text("详情")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)

            Button(action: onRestore) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("恢复为进行中")
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(isHovered ? 1 : 0.6))
        )
        .onHover { isHovered = $0 }
    }
}
