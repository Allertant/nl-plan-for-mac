import SwiftUI

/// 历史记录页
struct HistoryView: View {
    @State private var viewModel: HistoryViewModel
    @State private var returnToTodayRotation: Double = 0
    @State private var returnTodayHovered = false
    @Environment(AppState.self) private var appState

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

                    historyCalendarNavigationBar

                    HistoryMonthCalendarView(
                        monthStart: viewModel.displayedMonthStart,
                        summaries: viewModel.summaries
                    ) { summary in
                        viewModel.selectSummary(summary)
                    }
                    .id(viewModel.displayedMonthStart.yearMonthTitle)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
                    .animation(.easeInOut(duration: 0.22), value: viewModel.displayedMonthStart)

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
                } onViewDetail: {
                    let date = summary.date
                    viewModel.selectedSummary = nil
                    appState.currentPage = .historyDetail(date)
                }
                .zIndex(1)
            }
        }
        .frame(width: 360, height: 520)
        .onAppear {
            viewModel.loadCurrentMonth()
        }
    }

    private var historyCalendarNavigationBar: some View {
        HStack(spacing: 6) {
            navIconButton(systemName: "backward.end.fill") {
                viewModel.showPreviousYear()
            }
            .disabled(viewModel.isLoadingMonth)

            navIconButton(systemName: "chevron.left") {
                viewModel.showPreviousMonth()
            }
            .disabled(viewModel.isLoadingMonth)

            Spacer()

            Text(viewModel.displayedMonthStart.yearMonthTitle)
                .font(.system(size: 12, weight: .semibold))

            returnToTodayButton

            Spacer()

            navIconButton(systemName: "chevron.right") {
                viewModel.showNextMonth()
            }
            .disabled(viewModel.isLoadingMonth)

            navIconButton(systemName: "forward.end.fill") {
                viewModel.showNextYear()
            }
            .disabled(viewModel.isLoadingMonth)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func navIconButton(systemName: String, action: @escaping () -> Void) -> some View {
        NavIconButton(systemName: systemName, action: action)
    }

    private var returnToTodayButton: some View {
        Button {
            withAnimation(.linear(duration: 0.5)) {
                returnToTodayRotation += 360
            }
            viewModel.showCurrentMonth()
        } label: {
            ReturnToTodayRingIcon()
                .frame(width: 14, height: 14)
                .rotationEffect(.degrees(returnToTodayRotation))
                .frame(width: 30, height: 30)
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(returnTodayHovered ? Color.primary.opacity(0.08) : Color(nsColor: .controlBackgroundColor).opacity(0.65))
        )
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .onHover { returnTodayHovered = $0 }
        .opacity(viewModel.isDisplayingCurrentMonth ? 0.42 : 1)
        .disabled(viewModel.isLoadingMonth)
        .help("回到当前月份")
    }
}

private struct ReturnToTodayRingIcon: View {
    var body: some View {
        Circle()
            .trim(from: 0.06, to: 0.94)
            .stroke(style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
    }
}

private struct HistoryMonthCalendarView: View {
    let monthStart: Date
    let summaries: [DailySummaryEntity]
    let onSelectSummary: (DailySummaryEntity) -> Void

    private var calendar: Calendar { .current }

    private var weekSymbols: [String] {
        let symbols = calendar.shortWeekdaySymbols
        let first = max(0, calendar.firstWeekday - 1)
        return Array(symbols[first...] + symbols[..<first])
    }

    private var summaryByDay: [Int: DailySummaryEntity] {
        summaries.reduce(into: [Int: DailySummaryEntity]()) { result, summary in
            guard calendar.isDate(summary.date, equalTo: monthStart, toGranularity: .month) else { return }
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
    let onViewDetail: () -> Void

    @State private var detailButtonHovered = false

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(summary.date.dateString)
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button("查看详情") { onViewDetail() }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(detailButtonHovered ? Color.primary.opacity(0.08) : .clear)
                    )
                    .onHover { detailButtonHovered = $0 }
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
    private let levels: [Grade] = [
        .S,
        .A,
        .B,
        .C,
        .D,
        .E,
        .F,
    ]

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        LinearGradient(
                            colors: levels.map { $0.historyColor.opacity(0.9) },
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                HStack(spacing: 0) {
                    ForEach(levels, id: \.rawValue) { level in
                        Text(level.rawValue)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(level.legendTextColor)
                            .shadow(color: .black.opacity(level == .D ? 0 : 0.22), radius: 1, x: 0, y: 0.5)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(height: 24)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .padding(8)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private extension Grade {
    var legendTextColor: Color {
        self == .D ? .black.opacity(0.72) : .white
    }
}

private struct NavIconButton: View {
    let systemName: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isHovered ? Color.primary.opacity(0.08) : Color(nsColor: .controlBackgroundColor).opacity(0.65))
        )
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .onHover { isHovered = $0 }
    }
}

private extension Date {
    var yearMonthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: self)
    }
}
