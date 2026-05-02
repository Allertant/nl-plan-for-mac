import Foundation
import SwiftData

/// 项目安排数据操作仓库
final class ProjectArrangementRepository {

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func create(
        projectId: UUID,
        content: String,
        estimatedMinutes: Int = 30,
        deadline: Date? = nil,
        sortOrder: Int = 0
    ) throws -> ProjectArrangementEntity {
        let item = ProjectArrangementEntity(
            projectId: projectId,
            content: content,
            estimatedMinutes: estimatedMinutes,
            deadline: deadline,
            sortOrder: sortOrder
        )
        modelContext.insert(item)
        try modelContext.save()
        return item
    }

    func fetchByProject(projectId: UUID) throws -> [ProjectArrangementEntity] {
        let descriptor = FetchDescriptor<ProjectArrangementEntity>(
            predicate: #Predicate { $0.projectId == projectId },
            sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchById(_ id: UUID) throws -> ProjectArrangementEntity? {
        let descriptor = FetchDescriptor<ProjectArrangementEntity>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    func fetchPendingByProject(projectId: UUID) throws -> [ProjectArrangementEntity] {
        let pendingRaw = ArrangementStatus.pending.rawValue
        let descriptor = FetchDescriptor<ProjectArrangementEntity>(
            predicate: #Predicate { $0.projectId == projectId && $0.status == pendingRaw },
            sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchByArrangementId(arrangementId: UUID) throws -> ProjectArrangementEntity? {
        try fetchById(arrangementId)
    }

    func update(_ item: ProjectArrangementEntity) throws {
        item.updatedAt = .now
        try modelContext.save()
    }

    func delete(_ item: ProjectArrangementEntity) throws {
        modelContext.delete(item)
        try modelContext.save()
    }

    func deleteByProject(projectId: UUID) throws {
        let items = try fetchByProject(projectId: projectId)
        for item in items {
            modelContext.delete(item)
        }
        try modelContext.save()
    }

    func nextSortOrder(projectId: UUID) throws -> Int {
        let items = try fetchByProject(projectId: projectId)
        return (items.map(\.sortOrder).max() ?? -1) + 1
    }
}
