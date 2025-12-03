//
//  ModerationAuditStore.swift
//  MyTube
//
//  Created by Assistant on 12/03/25.
//

import CoreData
import Foundation
import OSLog

/// Manages audit trail for moderation actions
@MainActor
final class ModerationAuditStore: ObservableObject {

    private let persistence: PersistenceController
    private let logger = Logger(subsystem: "com.mytube", category: "ModerationAuditStore")

    init(persistence: PersistenceController) {
        self.persistence = persistence
    }

    /// Log a moderation action
    func logAction(
        type: ModerationActionType,
        actorKey: String,
        targetType: String? = nil,
        targetId: String? = nil,
        details: [String: String]? = nil
    ) async throws {
        try await performBackground { context in
            let entity = ModerationAuditEntity(context: context)
            entity.id = UUID()
            entity.actionType = type.rawValue
            entity.actorKey = actorKey
            entity.targetType = targetType
            entity.targetId = targetId
            entity.createdAt = Date()

            if let details = details,
               let data = try? JSONSerialization.data(withJSONObject: details) {
                entity.details = String(data: data, encoding: .utf8)
            }

            try context.save()
        }
    }

    /// Get audit trail for a specific report
    func auditTrail(forReportId reportId: UUID) async throws -> [ModerationAuditEntry] {
        try await fetchAuditTrail(targetType: "report", targetId: reportId.uuidString)
    }

    /// Get audit trail for a specific relationship
    func auditTrail(forRelationshipId relationshipId: UUID) async throws -> [ModerationAuditEntry] {
        try await fetchAuditTrail(targetType: "relationship", targetId: relationshipId.uuidString)
    }

    /// Get audit trail for a specific video
    func auditTrail(forVideoId videoId: String) async throws -> [ModerationAuditEntry] {
        try await fetchAuditTrail(targetType: "video", targetId: videoId)
    }

    /// Get all recent audit entries
    func recentAuditTrail(limit: Int = 100) async throws -> [ModerationAuditEntry] {
        try await performBackground { context in
            let request = ModerationAuditEntity.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(keyPath: \ModerationAuditEntity.createdAt, ascending: false)]
            request.fetchLimit = limit

            let entities = try context.fetch(request)
            return entities.map { ModerationAuditEntry(from: $0) }
        }
    }

    /// Get audit entries for a specific action type
    func auditTrail(forActionType actionType: ModerationActionType, limit: Int = 100) async throws -> [ModerationAuditEntry] {
        try await performBackground { context in
            let request = ModerationAuditEntity.fetchRequest()
            request.predicate = NSPredicate(format: "actionType == %@", actionType.rawValue)
            request.sortDescriptors = [NSSortDescriptor(keyPath: \ModerationAuditEntity.createdAt, ascending: false)]
            request.fetchLimit = limit

            let entities = try context.fetch(request)
            return entities.map { ModerationAuditEntry(from: $0) }
        }
    }

    /// Get audit entries by actor
    func auditTrail(byActor actorKey: String, limit: Int = 100) async throws -> [ModerationAuditEntry] {
        try await performBackground { context in
            let request = ModerationAuditEntity.fetchRequest()
            request.predicate = NSPredicate(format: "actorKey == %@", actorKey)
            request.sortDescriptors = [NSSortDescriptor(keyPath: \ModerationAuditEntity.createdAt, ascending: false)]
            request.fetchLimit = limit

            let entities = try context.fetch(request)
            return entities.map { ModerationAuditEntry(from: $0) }
        }
    }

    /// Delete old audit entries (for storage management)
    func pruneOldEntries(olderThan date: Date) async throws -> Int {
        try await performBackground { context in
            let request = ModerationAuditEntity.fetchRequest()
            request.predicate = NSPredicate(format: "createdAt < %@", date as NSDate)

            let entities = try context.fetch(request)
            let count = entities.count
            for entity in entities {
                context.delete(entity)
            }
            try context.save()
            return count
        }
    }

    // MARK: - Private

    private func fetchAuditTrail(targetType: String, targetId: String) async throws -> [ModerationAuditEntry] {
        try await performBackground { context in
            let request = ModerationAuditEntity.fetchRequest()
            request.predicate = NSPredicate(format: "targetType == %@ AND targetId == %@", targetType, targetId)
            request.sortDescriptors = [NSSortDescriptor(keyPath: \ModerationAuditEntity.createdAt, ascending: false)]

            let entities = try context.fetch(request)
            return entities.map { ModerationAuditEntry(from: $0) }
        }
    }

    private func performBackground<T>(
        _ block: @escaping (NSManagedObjectContext) throws -> T
    ) async throws -> T {
        let context = persistence.newBackgroundContext()
        return try await withCheckedThrowingContinuation { continuation in
            context.perform {
                do {
                    let result = try block(context)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
