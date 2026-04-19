import Foundation
import SwiftData

/// 解析队列数据操作仓库
final class ParseQueueRepository {

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func create(rawText: String) throws -> ParseQueueItemEntity {
        let item = ParseQueueItemEntity(rawText: rawText)
        modelContext.insert(item)
        try modelContext.save()
        return item
    }

    func fetchAll() throws -> [ParseQueueItemEntity] {
        let descriptor = FetchDescriptor<ParseQueueItemEntity>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchById(_ id: UUID) throws -> ParseQueueItemEntity? {
        let descriptor = FetchDescriptor<ParseQueueItemEntity>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    func update(_ item: ParseQueueItemEntity) throws {
        try modelContext.save()
    }

    func delete(_ item: ParseQueueItemEntity) throws {
        modelContext.delete(item)
        try modelContext.save()
    }
}
