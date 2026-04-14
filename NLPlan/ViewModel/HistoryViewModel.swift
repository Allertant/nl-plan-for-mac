import Foundation
import SwiftData

/// 历史记录 ViewModel
@Observable
final class HistoryViewModel {

    var summaries: [DailySummaryEntity] = []
    var selectedSummary: DailySummaryEntity?
    var errorMessage: String?

    let dayManager: DayManager

    init(dayManager: DayManager) {
        self.dayManager = dayManager
    }

    /// 加载当月历史
    func loadCurrentMonth() async {
        let calendar = Calendar.current
        let now = Date.now
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth)!

        do {
            summaries = try await dayManager.fetchHistory(from: startOfMonth, to: endOfMonth)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 选择某天的总结
    func selectSummary(_ summary: DailySummaryEntity) {
        selectedSummary = summary
    }
}
