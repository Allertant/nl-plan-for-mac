import SwiftUI

/// 历史记录页
struct HistoryView: View {
    @State private var viewModel: HistoryViewModel
    @Environment(AppState.self) private var appState
    @State private var hoveredSummary: DailySummaryEntity?

    init(dayManager: DayManager) {
        _viewModel = State(initialValue: HistoryViewModel(dayManager: dayManager))
    }

    var body: some View {
        ZStack {
            // 月历视图
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

                VStack(spacing: 10) {
                    HistoryGradeLegend()

                    HistoryMonthCalendarView(
                        summaries: viewModel.summaries,
                        hoveredSummary: $hoveredSummary
                    ) { summary in
                        viewModel.selectSummary(summary)
                    }

                    if let hoveredSummary {
                        HistoryHoverDetailView(summary: hoveredSummary)
                    } else {
                        Text("将鼠标移动到日期圆点上可查看当天详情")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    Spacer(minLength: 0)
                }
                .padding(12)

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

private struct HistoryMonthCalendarView: View {
    let summaries: [DailySummaryEntity]
    @Binding var hoveredSummary: DailySummaryEntity?
    let onSelectSummary: (DailySummaryEntity) -> Void

    private var calendar: Calendar { .current }

    private var monthStart: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: .now)) ?? .now
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: monthStart)
    }

    private var weekSymbols: [String] {
        let symbols = calendar.shortWeekdaySymbols
        let first = max(0, calendar.firstWeekday - 1)
        return Array(symbols[first...] + symbols[..<first])
    }

    private var summaryByDay: [Int: DailySummaryEntity] {
        summaries.reduce(into: [Int: DailySummaryEntity]()) { result, summary in
            let day = calendar.component(.day, from: summary.date)
            if let existing = result[day], existing.createdAt >= summary.createdAt {
                return
            }
            result[day] = summary
        }
    }

    private var dayCells: [HistoryDayCell] {
        guard
            let dayRange = calendar.range(of: .day, in: .month, for: monthStart),
            let firstDate = calendar.date(from: calendar.dateComponents([.year, .month], from: monthStart))
        else {
            return []
        }

        let firstWeekdayOfMonth = calendar.component(.weekday, from: firstDate)
        let leadingEmptyCount = (firstWeekdayOfMonth - calendar.firstWeekday + 7) % 7
        var cells: [HistoryDayCell] = Array(repeating: .empty, count: leadingEmptyCount)

        for day in dayRange {
            guard let date = calendar.date(bySetting: .day, value: day, of: monthStart) else { continue }
            cells.append(.day(day: day, date: date, summary: summaryByDay[day]))
        }

        while cells.count % 7 != 0 {
            cells.append(.empty)
        }

        return cells
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(monthTitle)
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                ForEach(weekSymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 8) {
                ForEach(Array(dayCells.enumerated()), id: \.offset) { _, cell in
                    switch cell {
                    case .empty:
                        Circle()
                            .fill(Color.clear)
                            .frame(width: 34, height: 34)
                    case .day(let day, _, let summary):
                        HistoryDayCircle(day: day, summary: summary)
                            .onHover { hovering in
                                guard let summary else { return }
                                hoveredSummary = hovering ? summary : nil
                            }
                            .onTapGesture {
                                guard let summary else { return }
                                onSelectSummary(summary)
                            }
                    }
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private enum HistoryDayCell {
    case empty
    case day(day: Int, date: Date, summary: DailySummaryEntity?)
}

private struct HistoryDayCircle: View {
    let day: Int
    let summary: DailySummaryEntity?

    private var fillColor: Color {
        guard let summary else { return Color(nsColor: .controlBackgroundColor).opacity(0.35) }
        return summary.gradeEnum.historyColor.opacity(0.9)
    }

    private var textColor: Color {
        summary == nil ? .secondary : .white
    }

    var body: some View {
        Circle()
            .fill(fillColor)
            .frame(width: 34, height: 34)
            .overlay(
                Text("\(day)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(textColor)
            )
            .overlay(
                Circle()
                    .stroke(Color.primary.opacity(summary == nil ? 0.08 : 0.2), lineWidth: 1)
            )
    }
}

private struct HistoryHoverDetailView: View {
    let summary: DailySummaryEntity

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(summary.date.dateString)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(summary.grade)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(summary.gradeEnum.historyColor)
            }

            Text(summary.summary)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text("完成 \(summary.completedCount)/\(summary.totalCount)")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(summary.gradeEnum.historyColor.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
