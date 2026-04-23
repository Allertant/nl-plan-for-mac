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
    var tasks: [TaskEntity] = []
    var incompleteNotes: [UUID: String] = [:]
    let settlementDate: Date

    private let dayManager: DayManager
    private var endDayTask: Task<Void, Never>?

    init(dayManager: DayManager, settlementDate: Date = .now) {
        self.dayManager = dayManager
        self.settlementDate = Calendar.current.startOfDay(for: settlementDate)
    }

    /// 加载今日总结
    func loadTodaySummary() async {
        await loadSettlementSummary()
    }

    /// 加载结算日总结
    func loadSettlementSummary() async {
        guard !isProcessing else { return }
        do {
            summary = try await dayManager.fetchSummary(date: settlementDate)
            tasks = try await dayManager.fetchMustDoTasks(date: settlementDate)
            incompleteNotes = Dictionary(
                uniqueKeysWithValues: incompleteTasks.map { ($0.id, incompleteNotes[$0.id] ?? "") }
            )
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
                let result = try await dayManager.settleDay(date: settlementDate, incompleteNotes: sanitizedIncompleteNotes)
                guard !Task.isCancelled else { return }
                summary = result
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
            if Calendar.current.isDateInToday(settlementDate) {
                try await dayManager.undoTodaySummary()
            }
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
            summary = try await dayManager.appealGrade(date: settlementDate, userFeedback: appealText)
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

    var incompleteTasks: [TaskEntity] {
        tasks.filter { $0.status != TaskStatus.done.rawValue }
    }

    var canSettle: Bool {
        incompleteTasks.allSatisfy { task in
            !(incompleteNotes[task.id]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
    }

    var sanitizedIncompleteNotes: [UUID: String] {
        incompleteNotes.reduce(into: [UUID: String]()) { result, pair in
            let note = pair.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !note.isEmpty {
                result[pair.key] = note
            }
        }
    }
}
