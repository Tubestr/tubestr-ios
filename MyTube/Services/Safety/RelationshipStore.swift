//
//  RelationshipStore.swift
//  MyTube
//
//  Created by Assistant on 12/03/25.
//

import Combine
import CoreData
import Foundation
import OSLog

/// Manages relationship state and lifecycle
@MainActor
final class RelationshipStore: ObservableObject {

    @Published private(set) var relationships: [RelationshipModel] = []

    private let persistence: PersistenceController
    private let logger = Logger(subsystem: "com.mytube", category: "RelationshipStore")

    init(persistence: PersistenceController) {
        self.persistence = persistence
        Task {
            await loadRelationships()
        }
    }

    // MARK: - CRUD Operations

    /// Create a new relationship when a group is established
    func createRelationship(
        localProfileId: UUID,
        remoteParentKey: String,
        remoteChildKey: String?,
        mlsGroupId: String
    ) async throws -> RelationshipModel {
        try await performBackground { context in
            // Check for existing relationship
            let request = RelationshipEntity.fetchRequest()
            request.predicate = NSPredicate(format: "mlsGroupId == %@", mlsGroupId)
            request.fetchLimit = 1

            if let existing = try context.fetch(request).first {
                return RelationshipModel(from: existing)
            }

            let entity = RelationshipEntity(context: context)
            entity.id = UUID()
            entity.localProfileId = localProfileId
            entity.remoteParentKey = remoteParentKey
            entity.remoteChildKey = remoteChildKey
            entity.mlsGroupId = mlsGroupId
            entity.state = RelationshipState.active.rawValue
            entity.createdAt = Date()
            entity.localReportCount = 0
            entity.remoteReportCount = 0
            entity.blockedByRemote = false

            try context.save()
            let model = RelationshipModel(from: entity)
            await MainActor.run {
                self.upsertInMemory(model)
            }
            return model
        }
    }

    /// Fetch relationship by MLS group ID
    func relationship(forGroupId groupId: String) -> RelationshipModel? {
        relationships.first { $0.mlsGroupId == groupId }
    }

    /// Fetch relationships for a local profile
    func relationships(forProfile profileId: UUID) -> [RelationshipModel] {
        relationships.filter { $0.localProfileId == profileId }
    }

    /// Fetch relationship by remote parent key
    func relationship(forRemoteParent key: String) -> RelationshipModel? {
        relationships.first { $0.remoteParentKey == key }
    }

    // MARK: - State Transitions

    /// Update relationship state with validation
    func updateState(
        relationshipId: UUID,
        newState: RelationshipState,
        reason: String?,
        changedBy: String
    ) async throws {
        try await performBackground { context in
            guard let entity = try self.fetchEntity(id: relationshipId, in: context) else {
                throw RelationshipError.notFound
            }

            guard let currentState = RelationshipState(rawValue: entity.state ?? "active") else {
                throw RelationshipError.invalidState
            }

            guard currentState.canTransition(to: newState) else {
                throw RelationshipError.invalidTransition(from: currentState, to: newState)
            }

            entity.state = newState.rawValue
            entity.stateReason = reason
            entity.stateChangedAt = Date()
            entity.stateChangedBy = changedBy

            try context.save()
            let model = RelationshipModel(from: entity)
            await MainActor.run {
                self.upsertInMemory(model)
            }
        }

        NotificationCenter.default.post(
            name: .relationshipStateChanged,
            object: nil,
            userInfo: ["relationshipId": relationshipId, "newState": newState.rawValue]
        )
    }

    /// Freeze a relationship (temporary pause)
    func freeze(relationshipId: UUID, reason: String?, by actorKey: String) async throws {
        try await updateState(
            relationshipId: relationshipId,
            newState: .frozen,
            reason: reason,
            changedBy: actorKey
        )
    }

    /// Unfreeze a relationship (resume)
    func unfreeze(relationshipId: UUID, by actorKey: String) async throws {
        try await updateState(
            relationshipId: relationshipId,
            newState: .active,
            reason: "Resumed by parent",
            changedBy: actorKey
        )
    }

    /// Block a relationship
    func block(relationshipId: UUID, reason: String?, by actorKey: String) async throws {
        try await updateState(
            relationshipId: relationshipId,
            newState: .blocked,
            reason: reason,
            changedBy: actorKey
        )

        // Delete local media for this relationship
        try await requestMediaDeletion(relationshipId: relationshipId)
    }

    /// Unblock a relationship
    func unblock(relationshipId: UUID, by actorKey: String) async throws {
        try await updateState(
            relationshipId: relationshipId,
            newState: .active,
            reason: "Unblocked by parent",
            changedBy: actorKey
        )
    }

    /// Remove a relationship (terminal)
    func remove(relationshipId: UUID, reason: String?, by actorKey: String) async throws {
        try await updateState(
            relationshipId: relationshipId,
            newState: .removed,
            reason: reason,
            changedBy: actorKey
        )

        // Delete local media for this relationship
        try await requestMediaDeletion(relationshipId: relationshipId)
    }

    // MARK: - Report Tracking

    /// Increment local report count (we reported them)
    func incrementLocalReportCount(relationshipId: UUID) async throws {
        try await performBackground { context in
            guard let entity = try self.fetchEntity(id: relationshipId, in: context) else { return }
            entity.localReportCount += 1
            try context.save()
            let model = RelationshipModel(from: entity)
            await MainActor.run {
                self.upsertInMemory(model)
            }
        }
    }

    /// Increment remote report count (they reported us)
    func incrementRemoteReportCount(relationshipId: UUID) async throws {
        try await performBackground { context in
            guard let entity = try self.fetchEntity(id: relationshipId, in: context) else { return }
            entity.remoteReportCount += 1
            try context.save()
            let model = RelationshipModel(from: entity)
            await MainActor.run {
                self.upsertInMemory(model)
            }
        }
    }

    /// Mark as blocked by remote party
    func markBlockedByRemote(relationshipId: UUID, blocked: Bool) async throws {
        try await performBackground { context in
            guard let entity = try self.fetchEntity(id: relationshipId, in: context) else { return }
            entity.blockedByRemote = blocked
            try context.save()
            let model = RelationshipModel(from: entity)
            await MainActor.run {
                self.upsertInMemory(model)
            }
        }
    }

    // MARK: - Activity Tracking

    /// Update last activity timestamp
    func recordActivity(relationshipId: UUID) async throws {
        try await performBackground { context in
            guard let entity = try self.fetchEntity(id: relationshipId, in: context) else { return }
            entity.lastActivityAt = Date()
            try context.save()
            // Don't refresh full list for activity updates
        }
    }

    /// Update parent notes
    func updateNotes(relationshipId: UUID, notes: String?) async throws {
        try await performBackground { context in
            guard let entity = try self.fetchEntity(id: relationshipId, in: context) else { return }
            entity.notes = notes
            try context.save()
            let model = RelationshipModel(from: entity)
            await MainActor.run {
                self.upsertInMemory(model)
            }
        }
    }

    /// Refresh relationships from persistence
    func refresh() async {
        await loadRelationships()
    }

    // MARK: - Private Helpers

    private func fetchEntity(id: UUID, in context: NSManagedObjectContext) throws -> RelationshipEntity? {
        let request = RelationshipEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func loadRelationships() async {
        let viewContext = persistence.viewContext
        let request = RelationshipEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \RelationshipEntity.createdAt, ascending: false)]

        do {
            let entities = try viewContext.fetch(request)
            relationships = entities.map { RelationshipModel(from: $0) }
        } catch {
            logger.error("Failed to load relationships: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func upsertInMemory(_ model: RelationshipModel) {
        var existing = relationships
        if let index = existing.firstIndex(where: { $0.id == model.id }) {
            existing[index] = model
        } else {
            existing.append(model)
        }
        relationships = existing.sorted { $0.createdAt > $1.createdAt }
    }

    private func requestMediaDeletion(relationshipId: UUID) async throws {
        guard let relationship = relationships.first(where: { $0.id == relationshipId }) else {
            return
        }

        NotificationCenter.default.post(
            name: .relationshipMediaDeletionRequested,
            object: nil,
            userInfo: ["mlsGroupId": relationship.mlsGroupId]
        )
    }

    private func performBackground<T>(
        _ block: @escaping (NSManagedObjectContext) async throws -> T
    ) async throws -> T {
        let context = persistence.newBackgroundContext()
        return try await withCheckedThrowingContinuation { continuation in
            context.perform {
                Task {
                    do {
                        let result = try await block(context)
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
}

// MARK: - Errors

enum RelationshipError: LocalizedError {
    case notFound
    case invalidState
    case invalidTransition(from: RelationshipState, to: RelationshipState)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Relationship not found"
        case .invalidState:
            return "Invalid relationship state"
        case .invalidTransition(let from, let to):
            return "Cannot transition from \(from.rawValue) to \(to.rawValue)"
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let relationshipMediaDeletionRequested = Notification.Name("relationshipMediaDeletionRequested")
    static let relationshipStateChanged = Notification.Name("relationshipStateChanged")
}
