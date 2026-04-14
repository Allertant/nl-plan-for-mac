import Foundation
import SwiftData

/// 总结页 ViewModel
@Observable
final class SummaryViewModel {

    var summary: DailySummaryEntity?
    var isProcessing: Bool = false
    var errorMessage: String?
    var appealText: String = ""
    var showAppealInput: Bool = false
    var isAppealing: Bool = false

    private let dayManager: DayManager

    init(dayManager: DayManager) {
        self.dayManager = dayManager
    }

    /// 加载今日总结
    func loadTodaySummary() async {
        do {
            summary = try await dayManager.fetchTodaySummary()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 结束今天
    func endDay() async {
        isProcessing = true
        errorMessage = nil
        do {
            summary = try await dayManager.endDay()
        } catch {
            errorMessage = error.localizedDescription
        }
        isProcessing = false
    }

    /// 驳斥评分
    func appealGrade() async {
        guard !appealText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isAppealing = true
        errorMessage = nil

        do {
            let today = Calendar.current.startOfDay(for: .now)
            summary = try await dayManager.appealGrade(date: today, userFeedback: appealText)
            appealText = ""
            showAppealInput = false
        } catch {
            errorMessage = error.localizedDescription
        }

        isAppealing = false
    }

    /// 是否可以申诉
    var canAppeal: Bool {
        guard let summary else { return false }
        return summary.appealCount < AppConstants.maxAppealCount
    }

    /// 剩余申诉次数
    var remainingAppeals: Int {
        guard let summary else { return AppConstants.maxAppealCount }
        return AppConstants.maxAppealCount - summary.appealCount
    }
}
