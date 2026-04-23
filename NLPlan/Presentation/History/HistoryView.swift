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
                    VStack(spacing: 10) {
                        HistoryGradeLegend()

                        LazyVStack(spacing: 8) {
                            ForEach(viewModel.summaries, id: \.id) { summary in
                                HistoryCard(summary: summary) {
                                    viewModel.selectSummary(summary)
                                }
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
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .onTapGesture {
                        viewModel.selectedSummary = nil
                    }

                HistoryDetailView(summary: summary) {
                    viewModel.selectedSummary = nil
                }
                .zIndex(1)
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

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // 等级
                Text(summary.grade)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(summary.gradeEnum.historyColor)
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
                .foregroundStyle(summary.gradeEnum.historyColor)

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
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 14, x: 0, y: 5)
    }
}

private struct HistoryGradeLegend: View {
    private let levels: [(label: String, color: Color)] = [
        ("S", .purple),
        ("A", .blue),
        ("B", .cyan),
        ("C", .green),
        ("D", .yellow),
        ("E", .orange),
        ("F", .red),
    ]

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("优")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("差")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 4) {
                ForEach(levels, id: \.label) { level in
                    ZStack {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(level.color.opacity(0.2))
                        Text(level.label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(level.color)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 22)
                }
            }
        }
        .padding(8)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private extension Grade {
    var historyColor: Color {
        switch self {
        case .S: return .purple
        case .A: return .blue
        case .B: return .cyan
        case .C: return .green
        case .D: return .yellow
        case .E: return .orange
        case .F: return .red
        }
    }
}
