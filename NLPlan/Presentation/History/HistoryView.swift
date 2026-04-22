import SwiftUI

/// 历史记录页
struct HistoryView: View {
    @State private var viewModel: HistoryViewModel
    @Environment(AppState.self) private var appState

    init(dayManager: DayManager) {
        _viewModel = State(initialValue: HistoryViewModel(dayManager: dayManager))
    }

    var body: some View {
        ZStack {
            // 列表
            VStack(spacing: 0) {
                HStack {
                    BackButton { appState.currentPage = .main }

                    Text("历史记录")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.summaries, id: \.id) { summary in
                            HistoryCard(summary: summary) {
                                viewModel.selectSummary(summary)
                            }
                        }
                    }
                    .padding(12)
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .padding(8)
                }
            }

            // 详情覆盖层
            if let summary = viewModel.selectedSummary {
                HistoryDetailView(summary: summary) {
                    viewModel.selectedSummary = nil
                }
            }
        }
        .frame(width: 360, height: 520)
        .onAppear {
            Task { await viewModel.loadCurrentMonth() }
        }
    }
}

/// 历史卡片
struct HistoryCard: View {
    let summary: DailySummaryEntity
    let onTap: () -> Void

    var gradeColor: Color {
        switch summary.gradeEnum {
        case .S: return .purple
        case .A: return .green
        case .B: return .blue
        case .C: return .orange
        case .D: return .red
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // 等级
                Text(summary.grade)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(gradeColor)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.date.dateString)
                        .font(.system(size: 13, weight: .medium))

                    Text(summary.summary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text("\(summary.completedCount)/\(summary.totalCount)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

/// 历史详情弹窗
struct HistoryDetailView: View {
    let summary: DailySummaryEntity
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(summary.date.dateString)
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Text(summary.grade)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(summary.gradeEnum == .S ? Color.purple : .primary)

            Text(summary.summary)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            if let suggestion = summary.suggestion, !suggestion.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("建议")
                        .font(.system(size: 12, weight: .semibold))
                    Text(suggestion)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 300, height: 300)
    }
}
