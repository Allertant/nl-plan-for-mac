import Foundation
import SwiftData
import SwiftUI

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
    private let monthSwitchAnimation = Animation.easeInOut(duration: 0.22)

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
                    withAnimation(self.monthSwitchAnimation) {
                        self.displayedMonthStart = monthStart
                        self.summaries = fetched
                        self.errorMessage = nil
                        self.isLoadingMonth = false
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    withAnimation(self.monthSwitchAnimation) {
                        self.displayedMonthStart = monthStart
                        self.summaries = []
                        self.errorMessage = error.localizedDescription
                        self.isLoadingMonth = false
                    }
                }
            }
        }
    }

    private func shiftMonth(by value: Int) {
        let calendar = Calendar.current
        guard let next = calendar.date(byAdding: .month, value: value, to: displayedMonthStart) else { return }
        selectedSummary = nil
        startMonthLoad(for: calendar.date(from: calendar.dateComponents([.year, .month], from: next)) ?? next)
    }

    private func shiftYear(by value: Int) {
        let calendar = Calendar.current
        guard let next = calendar.date(byAdding: .year, value: value, to: displayedMonthStart) else { return }
        selectedSummary = nil
        startMonthLoad(for: calendar.date(from: calendar.dateComponents([.year, .month], from: next)) ?? next)
    }

    /// 选择某天的总结
    func selectSummary(_ summary: DailySummaryEntity) {
        selectedSummary = summary
    }
}
