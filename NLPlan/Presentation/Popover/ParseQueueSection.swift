import SwiftUI

/// 解析队列列表
struct ParseQueueSection: View {
    @Bindable var viewModel: InputViewModel
    var onNavigateToDetail: (UUID) -> Void

    var body: some View {
        if !viewModel.queueItems.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(viewModel.queueItems) { item in
                    ParseQueueRow(item: item) {
                        onNavigateToDetail(item.id)
                    } onRetry: {
                        Task { await viewModel.retryQueueItem(id: item.id) }
                    }
                }
            }
        }
    }
}

/// 队列中的单行
private struct ParseQueueRow: View {
    let item: ParseQueueItem
    let onTap: () -> Void
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            statusIcon

            Text(item.displaySummary)
                .font(.system(size: 12))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            statusLabel
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onTapGesture {
            switch item.status {
            case .completed:
                onTap()
            case .failed:
                onRetry()
            default:
                break
            }
        }
    }

    // MARK: - 状态图标

    @ViewBuilder
    private var statusIcon: some View {
        switch item.status {
        case .waiting:
            Image(systemName: "clock")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        case .processing:
            ProgressView()
                .controlSize(.small)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.red)
        }
    }

    // MARK: - 状态标签

    @ViewBuilder
    private var statusLabel: some View {
        switch item.status {
        case .waiting:
            Text("等待中")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        case .processing:
            Text("解析中...")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        case .completed:
            if let tasks = item.parsedTasks {
                Text("\(tasks.count) 个任务")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        case .failed:
            Text("点击重试")
                .font(.system(size: 10))
                .foregroundStyle(.red.opacity(0.7))
        }
    }
}
