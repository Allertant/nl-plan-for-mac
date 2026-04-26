import Foundation
import SwiftData

/// 日终总结数据操作仓库
final class SummaryRepository {

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func create(
        date: Date,
        grade: Grade,
        summary: String,
        suggestion: String?,
        totalPlannedMinutes: Int,
        totalActualMinutes: Int,
        completedCount: Int,
        totalCount: Int,
        gradingBasis: String? = nil
    ) throws -> DailySummaryEntity {
        let entity = DailySummaryEntity(
            date: date,
            grade: grade.rawValue,
            summary: summary,
            suggestion: suggestion,
            totalPlannedMinutes: totalPlannedMinutes,
            totalActualMinutes: totalActualMinutes,
            completedCount: completedCount,
            totalCount: totalCount,
            gradingBasis: gradingBasis
        )
        modelContext.insert(entity)
        try modelContext.save()
        return entity
    }

    func fetch(date: Date) throws -> DailySummaryEntity? {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let descriptor = FetchDescriptor<DailySummaryEntity>(
            predicate: #Predicate { summary in
                summary.date >= startOfDay && summary.date < endOfDay
            }
        )
        return try modelContext.fetch(descriptor).first
    }

    func fetchRange(from: Date, to: Date) throws -> [DailySummaryEntity] {
        let descriptor = FetchDescriptor<DailySummaryEntity>(
            predicate: #Predicate { summary in
                summary.date >= from && summary.date < to
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func update(_ summary: DailySummaryEntity) throws {
        try modelContext.save()
    }

    func delete(_ summary: DailySummaryEntity) throws {
        modelContext.delete(summary)
        try modelContext.save()
    }

    func fetchAll() throws -> [DailySummaryEntity] {
        let descriptor = FetchDescriptor<DailySummaryEntity>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }
}
