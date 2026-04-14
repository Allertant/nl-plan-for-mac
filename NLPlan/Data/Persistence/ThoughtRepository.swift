import Foundation
import SwiftData

/// 想法数据操作仓库
final class ThoughtRepository {

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func create(rawText: String) throws -> ThoughtEntity {
        let thought = ThoughtEntity(rawText: rawText)
        modelContext.insert(thought)
        try modelContext.save()
        return thought
    }

    func markProcessed(_ thought: ThoughtEntity) throws {
        thought.processed = true
        try modelContext.save()
    }

    func fetchAll() throws -> [ThoughtEntity] {
        let descriptor = FetchDescriptor<ThoughtEntity>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }
}
