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
    private var endDayTask: Task<Void, Never>?

    init(dayManager: DayManager) {
        self.dayManager = dayManager
    }

    /// 加载今日总结
    func loadTodaySummary() async {
        guard !isProcessing else { return }
        do {
            summary = try await dayManager.fetchTodaySummary()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 结束今天
    func endDay() {
        isProcessing = true
        errorMessage = nil
        endDayTask = Task {
            do {
                summary = try await dayManager.endDay()
            } catch {
                if !Task.isCancelled {
                    errorMessage = error.localizedDescription
                }
            }
            endDayTask = nil
            isProcessing = false
        }
    }

    /// 取消评分（加载中）
    func cancelEndDay() {
        endDayTask?.cancel()
        endDayTask = nil
        isProcessing = false
        errorMessage = nil
    }

    /// 撤销评分（已完成）
    func undoEndDay() async {
        do {
            try await dayManager.undoTodaySummary()
            summary = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
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
