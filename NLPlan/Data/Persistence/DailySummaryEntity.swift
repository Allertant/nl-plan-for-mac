import Foundation
import SwiftData

/// 日终总结实体
@Model
final class DailySummaryEntity {
    @Attribute(.unique) var id: UUID
    var date: Date
    var grade: String        // "S" / "A" / "B" / "C" / "D" / "E" / "F"
    var summary: String
    var suggestion: String?
    var totalPlannedMinutes: Int
    var totalActualMinutes: Int
    var completedCount: Int
    var totalCount: Int
    var syncedToNotes: Bool
    var createdAt: Date
    var appealCount: Int
    var gradingBasis: String?

    @Transient
    var gradeEnum: Grade {
        get { Grade(rawValue: grade) ?? .F }
        set { grade = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        date: Date = .now,
        grade: String = "F",
        summary: String = "",
        suggestion: String? = nil,
        totalPlannedMinutes: Int = 0,
        totalActualMinutes: Int = 0,
        completedCount: Int = 0,
        totalCount: Int = 0,
        syncedToNotes: Bool = false,
        createdAt: Date = .now,
        appealCount: Int = 0,
        gradingBasis: String? = nil
    ) {
        self.id = id
        self.date = date
        self.grade = grade
        self.summary = summary
        self.suggestion = suggestion
        self.totalPlannedMinutes = totalPlannedMinutes
        self.totalActualMinutes = totalActualMinutes
        self.completedCount = completedCount
        self.totalCount = totalCount
        self.syncedToNotes = syncedToNotes
        self.createdAt = createdAt
        self.appealCount = appealCount
        self.gradingBasis = gradingBasis
    }
}
