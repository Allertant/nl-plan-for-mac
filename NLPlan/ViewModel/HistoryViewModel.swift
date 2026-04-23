import Foundation
import SwiftData

/// 历史记录 ViewModel
@MainActor
@Observable
final class HistoryViewModel {

    var summaries: [DailySummaryEntity] = []
    var selectedSummary: DailySummaryEntity?
    var errorMessage: String?
    var displayedMonthStart: Date
    var isLoadingMonth: Bool = false

    let dayManager: DayManager
    private var monthLoadTask: Task<Void, Never>?

    init(dayManager: DayManager) {
        self.dayManager = dayManager
        let calendar = Calendar.current
        self.displayedMonthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: .now)
        ) ?? .now
    }

    /// 加载当月历史
    func loadCurrentMonth() {
        startMonthLoad(for: displayedMonthStart)
    }

    func showPreviousMonth() {
        shiftMonth(by: -1)
    }

    func showNextMonth() {
        shiftMonth(by: 1)
    }

    func showPreviousYear() {
        shiftYear(by: -1)
    }

    func showNextYear() {
        shiftYear(by: 1)
    }

    // MARK: - Private

    private func startMonthLoad(for monthStart: Date) {
        monthLoadTask?.cancel()
        isLoadingMonth = true
        let calendar = Calendar.current
        let endOfMonth = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart

        monthLoadTask = Task { [dayManager] in
            do {
                let fetched = try await dayManager.fetchHistory(from: monthStart, to: endOfMonth)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.displayedMonthStart == monthStart else { return }
                    self.summaries = fetched
                    self.errorMessage = nil
                    self.isLoadingMonth = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.displayedMonthStart == monthStart else { return }
                    self.errorMessage = error.localizedDescription
                    self.isLoadingMonth = false
                }
            }
        }
    }

    private func shiftMonth(by value: Int) {
        let calendar = Calendar.current
        guard let next = calendar.date(byAdding: .month, value: value, to: displayedMonthStart) else { return }
        displayedMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: next)) ?? next
        selectedSummary = nil
        startMonthLoad(for: displayedMonthStart)
    }

    private func shiftYear(by value: Int) {
        let calendar = Calendar.current
        guard let next = calendar.date(byAdding: .year, value: value, to: displayedMonthStart) else { return }
        displayedMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: next)) ?? next
        selectedSummary = nil
        startMonthLoad(for: displayedMonthStart)
    }

    /// 选择某天的总结
    func selectSummary(_ summary: DailySummaryEntity) {
        selectedSummary = summary
    }
}
