//
//  RelationshipModels.swift
//  MyTube
//
//  Created by Assistant on 12/03/25.
//

import Foundation

/// State of a family relationship
enum RelationshipState: String, Codable, CaseIterable, Sendable {
    case active = "active"       // Normal operation
    case frozen = "frozen"       // Temporarily paused
    case blocked = "blocked"     // Blocked, requires explicit unblock
    case removed = "removed"     // Relationship ended

    var allowsReceiving: Bool {
        self == .active
    }

    var allowsSending: Bool {
        self == .active
    }

    var displayName: String {
        switch self {
        case .active: return "Active"
        case .frozen: return "Paused"
        case .blocked: return "Blocked"
        case .removed: return "Removed"
        }
    }

    /// Valid transitions from this state
    var validTransitions: Set<RelationshipState> {
        switch self {
        case .active: return [.frozen, .blocked, .removed]
        case .frozen: return [.active, .blocked, .removed]
        case .blocked: return [.active, .removed]
        case .removed: return [] // Terminal state
        }
    }

    func canTransition(to newState: RelationshipState) -> Bool {
        validTransitions.contains(newState)
    }
}

/// Domain model for a family relationship
struct RelationshipModel: Identifiable, Sendable {
    let id: UUID
    let localProfileId: UUID
    let remoteParentKey: String
    let remoteChildKey: String?
    let mlsGroupId: String
    var state: RelationshipState
    var stateReason: String?
    var stateChangedAt: Date?
    var stateChangedBy: String?
    let createdAt: Date
    var lastActivityAt: Date?
    var notes: String?
    var localReportCount: Int
    var remoteReportCount: Int
    var blockedByRemote: Bool

    var isHealthy: Bool {
        state == .active && localReportCount == 0 && remoteReportCount == 0
    }

    var totalReportCount: Int {
        localReportCount + remoteReportCount
    }

    init(
        id: UUID,
        localProfileId: UUID,
        remoteParentKey: String,
        remoteChildKey: String?,
        mlsGroupId: String,
        state: RelationshipState,
        stateReason: String?,
        stateChangedAt: Date?,
        stateChangedBy: String?,
        createdAt: Date,
        lastActivityAt: Date?,
        notes: String?,
        localReportCount: Int,
        remoteReportCount: Int,
        blockedByRemote: Bool
    ) {
        self.id = id
        self.localProfileId = localProfileId
        self.remoteParentKey = remoteParentKey
        self.remoteChildKey = remoteChildKey
        self.mlsGroupId = mlsGroupId
        self.state = state
        self.stateReason = stateReason
        self.stateChangedAt = stateChangedAt
        self.stateChangedBy = stateChangedBy
        self.createdAt = createdAt
        self.lastActivityAt = lastActivityAt
        self.notes = notes
        self.localReportCount = localReportCount
        self.remoteReportCount = remoteReportCount
        self.blockedByRemote = blockedByRemote
    }

    init(from entity: RelationshipEntity) {
        self.id = entity.id ?? UUID()
        self.localProfileId = entity.localProfileId ?? UUID()
        self.remoteParentKey = entity.remoteParentKey ?? ""
        self.remoteChildKey = entity.remoteChildKey
        self.mlsGroupId = entity.mlsGroupId ?? ""
        self.state = RelationshipState(rawValue: entity.state ?? "active") ?? .active
        self.stateReason = entity.stateReason
        self.stateChangedAt = entity.stateChangedAt
        self.stateChangedBy = entity.stateChangedBy
        self.createdAt = entity.createdAt ?? Date()
        self.lastActivityAt = entity.lastActivityAt
        self.notes = entity.notes
        self.localReportCount = Int(entity.localReportCount)
        self.remoteReportCount = Int(entity.remoteReportCount)
        self.blockedByRemote = entity.blockedByRemote
    }
}

/// Action types for moderation audit trail
enum ModerationActionType: String, Codable, Sendable {
    // Report actions
    case reportSubmitted = "report_submitted"
    case reportAcknowledged = "report_acknowledged"
    case reportDismissed = "report_dismissed"
    case reportActioned = "report_actioned"

    // Relationship actions
    case relationshipCreated = "relationship_created"
    case relationshipFrozen = "relationship_frozen"
    case relationshipUnfrozen = "relationship_unfrozen"
    case relationshipBlocked = "relationship_blocked"
    case relationshipUnblocked = "relationship_unblocked"
    case relationshipRemoved = "relationship_removed"

    // Video actions
    case videoBlocked = "video_blocked"
    case videoRemoved = "video_removed"
    case videoRestored = "video_restored"

    // Moderator actions
    case moderatorWarning = "moderator_warning"
    case moderatorAction = "moderator_action"
}

/// Domain model for audit trail entries
struct ModerationAuditEntry: Identifiable, Sendable {
    let id: UUID
    let actionType: ModerationActionType
    let actorKey: String
    let targetType: String?
    let targetId: String?
    let details: [String: String]?
    let createdAt: Date

    init(
        id: UUID,
        actionType: ModerationActionType,
        actorKey: String,
        targetType: String?,
        targetId: String?,
        details: [String: String]?,
        createdAt: Date
    ) {
        self.id = id
        self.actionType = actionType
        self.actorKey = actorKey
        self.targetType = targetType
        self.targetId = targetId
        self.details = details
        self.createdAt = createdAt
    }

    init(from entity: ModerationAuditEntity) {
        self.id = entity.id ?? UUID()
        self.actionType = ModerationActionType(rawValue: entity.actionType ?? "") ?? .reportSubmitted
        self.actorKey = entity.actorKey ?? ""
        self.targetType = entity.targetType
        self.targetId = entity.targetId
        self.createdAt = entity.createdAt ?? Date()

        if let detailsString = entity.details,
           let data = detailsString.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            self.details = json
        } else {
            self.details = nil
        }
    }
}
