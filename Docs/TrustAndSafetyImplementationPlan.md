# Tubestr Trust & Safety — Technical Implementation Plan

> Full technical specification for implementing T&S features in the MyTube codebase.
> Designed for agent-based implementation across multiple phases.

## Table of Contents

1. [Overview & Architecture Decisions](#1-overview--architecture-decisions)
2. [Phase 1: Data Model Foundation](#2-phase-1-data-model-foundation)
3. [Phase 2: 3-Level Reporting System](#3-phase-2-3-level-reporting-system)
4. [Phase 3: Relationship State Management](#4-phase-3-relationship-state-management)
5. [Phase 4: Moderation Infrastructure](#5-phase-4-moderation-infrastructure)
6. [Phase 5: Content Removal Enhancements](#6-phase-5-content-removal-enhancements)
7. [Testing Strategy](#7-testing-strategy)
8. [File Reference](#8-file-reference)

---

## 1. Overview & Architecture Decisions

### 1.1 Goals

Build the Trust & Safety framework for Tubestr (MyTube), enabling:
- **3-level reporting**: Peer → Parent → Moderator escalation
- **Relationship lifecycle**: Active/frozen/blocked/removed states
- **Content removal**: Enhanced tombstone and lifecycle handling
- **Moderation infrastructure**: Audit trails, moderator actions, relay routing

### 1.2 Key Architecture Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Report routing | Same kind 4547 with `level` field | Backward compatible, simpler than new kinds |
| Level 2 reports | Published to Marmot | Both parents need visibility |
| Level 3 relay | `wss://no.str.cr` in publish list | Dedicated moderation relay |
| Relationship state | New Core Data entity | Clean separation, audit trail support |
| Blocked relationships | Delete local media | Privacy protection, storage savings |
| Pattern detection | Deferred | Out of scope for initial implementation |

### 1.3 Existing Infrastructure

The codebase already has:
- `ReportMessage` (kind 4547) with videoId, subjectChild, reason, note, by, ts
- `ReportStore`, `ReportCoordinator`, `ReportAbuseSheet`
- `VideoContentScanner` with Vision + NSFW model
- Tombstones (kind 30302) via `NostrEventReducer`
- `VideoLifecycleMessage` for revoke/delete (kinds 4544/4545)
- Parent controls via `ParentalControlsStore`

### 1.4 Message Flow Reference

```
Creation → MarmotShareService → MdkActor.createMessage() → MarmotTransport.publish()
                                                                    ↓
Reception ← MarmotProjectionStore ← MdkActor.processMessage() ← SyncCoordinator
                    ↓
            Core Data (ReportEntity, RemoteVideoEntity, etc.)
```

---

## 2. Phase 1: Data Model Foundation

**Goal**: Establish all data models and stores without modifying existing behavior.

### 2.1 Extend ReportMessage Schema

**File**: `MyTube/Services/Marmot/MarmotMessageModels.swift`

Update `ReportMessage` struct:

```swift
struct ReportMessage: Codable, Sendable {
    let t: String                    // "mytube/report"
    let videoId: String
    let subjectChild: String
    let reason: String
    let note: String?
    let by: String                   // Parent key (signer)
    let ts: Double

    // NEW FIELDS (optional for backward compatibility):
    let level: Int?                  // 1=peer, 2=parent, 3=moderator (default: 1)
    let recipientType: String?       // "group", "parents", "moderators"
    let reporterChild: String?       // Child profile UUID who initiated
    let reportId: String?            // UUID for tracking across systems

    // Computed property for backward compatibility
    var resolvedLevel: Int { level ?? 1 }
}
```

**Encoding keys** (snake_case for wire format):
```swift
enum CodingKeys: String, CodingKey {
    case t, videoId = "video_id", subjectChild = "subject_child"
    case reason, note, by, ts
    case level, recipientType = "recipient_type"
    case reporterChild = "reporter_child", reportId = "report_id"
}
```

### 2.2 Add ReportLevel Enum

**File**: `MyTube/Domain/ReportModels.swift`

Add after existing `ReportReason` enum:

```swift
/// The escalation level of a report
enum ReportLevel: Int, Codable, CaseIterable, Sendable {
    case peer = 1        // Direct feedback to the other family
    case parent = 2      // Escalate to both parents for guidance
    case moderator = 3   // Escalate to Tubestr safety team

    var displayName: String {
        switch self {
        case .peer: return "Tell Them"
        case .parent: return "Ask Parents"
        case .moderator: return "Report to Tubestr"
        }
    }

    var description: String {
        switch self {
        case .peer: return "Let them know this doesn't feel good"
        case .parent: return "Ask both parents to help figure this out"
        case .moderator: return "This is serious and needs Tubestr's help"
        }
    }

    var recipientType: String {
        switch self {
        case .peer: return "group"
        case .parent: return "parents"
        case .moderator: return "moderators"
        }
    }
}
```

### 2.3 Update ReportEntity in Core Data

**File**: `MyTube/MyTube.xcdatamodeld/MyTube.xcdatamodel/contents`

Add attributes to `ReportEntity`:

| Attribute | Type | Default | Notes |
|-----------|------|---------|-------|
| `level` | Integer 16 | 1 | ReportLevel raw value |
| `reporterChild` | String | nil | Child UUID who initiated |
| `recipientType` | String | "group" | Target audience |
| `reportId` | UUID | auto | Unique report identifier |

### 2.4 Create RelationshipEntity in Core Data

**File**: `MyTube/MyTube.xcdatamodeld/MyTube.xcdatamodel/contents`

New entity `Relationship`:

| Attribute | Type | Optional | Notes |
|-----------|------|----------|-------|
| `id` | UUID | No | Primary key |
| `localProfileId` | UUID | No | Local child profile |
| `remoteParentKey` | String | No | Remote parent npub |
| `remoteChildKey` | String | Yes | Remote child npub (if known) |
| `mlsGroupId` | String | No | Associated MLS group |
| `state` | String | No | "active", "frozen", "blocked", "removed" |
| `stateReason` | String | Yes | Why state changed |
| `stateChangedAt` | Date | Yes | When state last changed |
| `stateChangedBy` | String | Yes | Who changed state (npub) |
| `createdAt` | Date | No | Relationship creation |
| `lastActivityAt` | Date | Yes | Last message activity |
| `notes` | String | Yes | Parent notes |
| `localReportCount` | Integer 16 | No | Reports we sent (default: 0) |
| `remoteReportCount` | Integer 16 | No | Reports we received (default: 0) |
| `blockedByRemote` | Boolean | No | If they blocked us (default: false) |

### 2.5 Create ModerationAuditEntity in Core Data

**File**: `MyTube/MyTube.xcdatamodeld/MyTube.xcdatamodel/contents`

New entity `ModerationAudit`:

| Attribute | Type | Optional | Notes |
|-----------|------|----------|-------|
| `id` | UUID | No | Primary key |
| `actionType` | String | No | Action type identifier |
| `actorKey` | String | No | Who performed action (npub) |
| `targetType` | String | Yes | "report", "relationship", "video" |
| `targetId` | String | Yes | ID of target entity |
| `details` | String | Yes | JSON blob with action details |
| `createdAt` | Date | No | When action occurred |

### 2.6 Create RelationshipModels.swift

**File**: `MyTube/Domain/RelationshipModels.swift` (new file)

```swift
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
    let details: [String: Any]?
    let createdAt: Date
}
```

### 2.7 Create RelationshipStore.swift

**File**: `MyTube/Services/Safety/RelationshipStore.swift` (new file)

```swift
import Foundation
import CoreData
import Combine

/// Manages relationship state and lifecycle
@MainActor
final class RelationshipStore: ObservableObject {

    @Published private(set) var relationships: [RelationshipModel] = []

    private let persistenceController: PersistenceController
    private let context: NSManagedObjectContext

    init(persistenceController: PersistenceController) {
        self.persistenceController = persistenceController
        self.context = persistenceController.container.viewContext
    }

    // MARK: - CRUD Operations

    /// Create a new relationship when a group is established
    func createRelationship(
        localProfileId: UUID,
        remoteParentKey: String,
        remoteChildKey: String?,
        mlsGroupId: String
    ) async throws -> RelationshipModel {
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
        await refreshRelationships()

        return RelationshipModel(from: entity)
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
        guard let entity = try fetchEntity(id: relationshipId) else {
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
        await refreshRelationships()
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
        try await deleteMediaForRelationship(relationshipId: relationshipId)
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
        try await deleteMediaForRelationship(relationshipId: relationshipId)
    }

    // MARK: - Report Tracking

    /// Increment local report count (we reported them)
    func incrementLocalReportCount(relationshipId: UUID) async throws {
        guard let entity = try fetchEntity(id: relationshipId) else { return }
        entity.localReportCount += 1
        try context.save()
        await refreshRelationships()
    }

    /// Increment remote report count (they reported us)
    func incrementRemoteReportCount(relationshipId: UUID) async throws {
        guard let entity = try fetchEntity(id: relationshipId) else { return }
        entity.remoteReportCount += 1
        try context.save()
        await refreshRelationships()
    }

    /// Mark as blocked by remote party
    func markBlockedByRemote(relationshipId: UUID, blocked: Bool) async throws {
        guard let entity = try fetchEntity(id: relationshipId) else { return }
        entity.blockedByRemote = blocked
        try context.save()
        await refreshRelationships()
    }

    // MARK: - Activity Tracking

    /// Update last activity timestamp
    func recordActivity(relationshipId: UUID) async throws {
        guard let entity = try fetchEntity(id: relationshipId) else { return }
        entity.lastActivityAt = Date()
        try context.save()
        // Don't refresh full list for activity updates
    }

    /// Update parent notes
    func updateNotes(relationshipId: UUID, notes: String?) async throws {
        guard let entity = try fetchEntity(id: relationshipId) else { return }
        entity.notes = notes
        try context.save()
        await refreshRelationships()
    }

    // MARK: - Private Helpers

    private func fetchEntity(id: UUID) throws -> RelationshipEntity? {
        let request = RelationshipEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func refreshRelationships() async {
        let request = RelationshipEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \RelationshipEntity.createdAt, ascending: false)]

        do {
            let entities = try context.fetch(request)
            relationships = entities.map { RelationshipModel(from: $0) }
        } catch {
            print("Failed to fetch relationships: \(error)")
        }
    }

    private func deleteMediaForRelationship(relationshipId: UUID) async throws {
        guard let relationship = relationships.first(where: { $0.id == relationshipId }) else {
            return
        }

        // Find all remote videos from this group and delete their media
        // This will be wired to RemoteVideoStore in Phase 3
        NotificationCenter.default.post(
            name: .relationshipMediaDeletionRequested,
            object: nil,
            userInfo: ["mlsGroupId": relationship.mlsGroupId]
        )
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

// MARK: - Entity Extension

extension RelationshipModel {
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
```

### 2.8 Create ModerationAuditStore.swift

**File**: `MyTube/Services/Safety/ModerationAuditStore.swift` (new file)

```swift
import Foundation
import CoreData

/// Manages audit trail for moderation actions
@MainActor
final class ModerationAuditStore: ObservableObject {

    private let persistenceController: PersistenceController
    private let context: NSManagedObjectContext

    init(persistenceController: PersistenceController) {
        self.persistenceController = persistenceController
        self.context = persistenceController.container.viewContext
    }

    /// Log a moderation action
    func logAction(
        type: ModerationActionType,
        actorKey: String,
        targetType: String? = nil,
        targetId: String? = nil,
        details: [String: Any]? = nil
    ) async throws {
        let entity = ModerationAuditEntity(context: context)
        entity.id = UUID()
        entity.actionType = type.rawValue
        entity.actorKey = actorKey
        entity.targetType = targetType
        entity.targetId = targetId
        entity.createdAt = Date()

        if let details = details {
            entity.details = try? JSONSerialization.data(withJSONObject: details)
                .flatMap { String(data: $0, encoding: .utf8) }
        }

        try context.save()
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
        let request = ModerationAuditEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ModerationAuditEntity.createdAt, ascending: false)]
        request.fetchLimit = limit

        let entities = try context.fetch(request)
        return entities.map { ModerationAuditEntry(from: $0) }
    }

    private func fetchAuditTrail(targetType: String, targetId: String) async throws -> [ModerationAuditEntry] {
        let request = ModerationAuditEntity.fetchRequest()
        request.predicate = NSPredicate(format: "targetType == %@ AND targetId == %@", targetType, targetId)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ModerationAuditEntity.createdAt, ascending: false)]

        let entities = try context.fetch(request)
        return entities.map { ModerationAuditEntry(from: $0) }
    }
}

// MARK: - Entity Extension

extension ModerationAuditEntry {
    init(from entity: ModerationAuditEntity) {
        self.id = entity.id ?? UUID()
        self.actionType = ModerationActionType(rawValue: entity.actionType ?? "") ?? .reportSubmitted
        self.actorKey = entity.actorKey ?? ""
        self.targetType = entity.targetType
        self.targetId = entity.targetId
        self.createdAt = entity.createdAt ?? Date()

        if let detailsString = entity.details,
           let data = detailsString.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            self.details = json
        } else {
            self.details = nil
        }
    }
}
```

### 2.9 Wire into AppEnvironment

**File**: `MyTube/AppEnvironment.swift`

Add properties and initialization:

```swift
// Add to AppEnvironment class:

let relationshipStore: RelationshipStore
let moderationAuditStore: ModerationAuditStore

// In init():
self.relationshipStore = RelationshipStore(persistenceController: persistenceController)
self.moderationAuditStore = ModerationAuditStore(persistenceController: persistenceController)
```

---

## 3. Phase 2: 3-Level Reporting System

**Goal**: Implement level-based report routing and UI.

### 3.1 Update ReportCoordinator Routing

**File**: `MyTube/Services/Safety/ReportCoordinator.swift`

Replace/extend `submitReport` method:

```swift
/// Submit a report with level-based routing
func submitReport(
    videoId: String,
    subjectChild: String,
    reason: ReportReason,
    note: String?,
    level: ReportLevel,
    reporterChild: String?,
    action: ReportAction
) async throws {
    guard let parentIdentity = try? await identityStore.getParentIdentity() else {
        throw ReportError.noParentIdentity
    }

    let reportId = UUID()
    let message = ReportMessage(
        t: "mytube/report",
        videoId: videoId,
        subjectChild: subjectChild,
        reason: reason.rawValue,
        note: note,
        by: parentIdentity.publicKey,
        ts: Date().timeIntervalSince1970,
        level: level.rawValue,
        recipientType: level.recipientType,
        reporterChild: reporterChild,
        reportId: reportId.uuidString
    )

    // Store report locally first
    try await reportStore.createReport(
        id: reportId,
        message: message,
        level: level,
        isOutbound: true
    )

    // Log audit entry
    try await moderationAuditStore.logAction(
        type: .reportSubmitted,
        actorKey: parentIdentity.publicKey,
        targetType: "video",
        targetId: videoId,
        details: [
            "level": level.rawValue,
            "reason": reason.rawValue,
            "subjectChild": subjectChild
        ]
    )

    // Route based on level
    switch level {
    case .peer:
        try await publishToGroup(message: message, videoId: videoId)

    case .parent:
        try await publishToParents(message: message, videoId: videoId)

    case .moderator:
        try await publishToModerators(message: message)
    }

    // Apply local action if requested
    if action != .none {
        try await applyReportAction(action, subjectChild: subjectChild, videoId: videoId)
    }

    // Update relationship report count
    if let groupId = resolveGroupId(forVideoId: videoId),
       let relationship = relationshipStore.relationship(forGroupId: groupId) {
        try await relationshipStore.incrementLocalReportCount(relationshipId: relationship.id)
    }
}

/// Level 1: Publish to the originating MLS group
private func publishToGroup(message: ReportMessage, videoId: String) async throws {
    guard let groupId = resolveGroupId(forVideoId: videoId) else {
        throw ReportError.groupNotFound
    }
    try await marmotShareService.publishReport(message, toGroup: groupId)
}

/// Level 2: Publish to group so both parents see it
private func publishToParents(message: ReportMessage, videoId: String) async throws {
    // Level 2 reports are still published to the group, but marked as parent-level
    // Both parents in the group can see and respond
    guard let groupId = resolveGroupId(forVideoId: videoId) else {
        throw ReportError.groupNotFound
    }
    try await marmotShareService.publishReport(message, toGroup: groupId)
}

/// Level 3: Publish to moderation relays
private func publishToModerators(message: ReportMessage) async throws {
    try await marmotTransport.publishToModerationRelays(message: message)
}

private func resolveGroupId(forVideoId videoId: String) -> String? {
    // Look up video to find its group
    remoteVideoStore.video(byId: videoId)?.mlsGroupId
}
```

### 3.2 Add Moderation Relay Publishing

**File**: `MyTube/Services/Marmot/MarmotTransport.swift`

Add method for Level 3 publishing:

```swift
/// Moderation relay for Level 3 reports
private let moderationRelay = "wss://no.str.cr"

/// Publish a report to moderation relays (Level 3)
func publishToModerationRelays(message: ReportMessage) async throws {
    let jsonData = try JSONEncoder().encode(message)
    guard let jsonString = String(data: jsonData, encoding: .utf8) else {
        throw TransportError.encodingFailed
    }

    // Create unsigned event
    let event = NostrEvent(
        kind: MarmotMessageKind.report.rawValue,
        content: jsonString,
        tags: [
            ["t", message.t],
            ["level", String(message.level ?? 3)],
            ["video_id", message.videoId]
        ]
    )

    // Sign with parent key
    let signedEvent = try await signEvent(event)

    // Get current relays and ensure moderation relay is included
    var relays = resolveRelays()
    if !relays.contains(moderationRelay) {
        relays.append(moderationRelay)
    }

    // Publish to all relays including moderation relay
    try await publish(event: signedEvent, relays: relays)
}
```

### 3.3 Update ReportAbuseSheet UI

**File**: `MyTube/SharedUI/Reporting/ReportAbuseSheet.swift`

Add level picker with kid-friendly copy:

```swift
struct ReportAbuseSheet: View {
    @State private var selectedReason: ReportReason = .other
    @State private var selectedLevel: ReportLevel = .peer
    @State private var note: String = ""
    @State private var shouldUnfollow = false
    @State private var shouldBlock = false

    let videoId: String
    let subjectChildName: String?
    let onSubmit: (ReportReason, String?, ReportLevel, ReportAction) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                // Level Selection (kid-friendly)
                Section {
                    ForEach(ReportLevel.allCases, id: \.self) { level in
                        LevelOptionRow(
                            level: level,
                            isSelected: selectedLevel == level,
                            onTap: { selectedLevel = level }
                        )
                    }
                } header: {
                    Text("What would you like to do?")
                }

                // Reason Selection
                Section {
                    Picker("Reason", selection: $selectedReason) {
                        ForEach(ReportReason.allCases, id: \.self) { reason in
                            Text(reason.displayName).tag(reason)
                        }
                    }
                } header: {
                    Text("What's the problem?")
                }

                // Optional Note
                Section {
                    TextField("Tell us more (optional)", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("More details")
                }

                // Actions (only show for Level 1)
                if selectedLevel == .peer {
                    Section {
                        Toggle("Stop seeing their videos", isOn: $shouldUnfollow)
                        Toggle("Block this family", isOn: $shouldBlock)
                    } header: {
                        Text("Additional actions")
                    }
                }
            }
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        let action: ReportAction = shouldBlock ? .block : (shouldUnfollow ? .unfollow : .none)
                        onSubmit(selectedReason, note.isEmpty ? nil : note, selectedLevel, action)
                    }
                }
            }
        }
    }
}

struct LevelOptionRow: View {
    let level: ReportLevel
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(level.displayName)
                        .font(.headline)
                    Text(level.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
```

### 3.4 Update MarmotProjectionStore for Incoming Reports

**File**: `MyTube/Services/Marmot/MarmotProjectionStore.swift`

Update `projectReport` to handle level field:

```swift
func projectReport(content: String, fromGroup groupId: String, processedAt: Date) async throws {
    let data = Data(content.utf8)
    let message = try decoder.decode(ReportMessage.self, from: data)

    let level = ReportLevel(rawValue: message.level ?? 1) ?? .peer
    let createdAt = Date(timeIntervalSince1970: message.ts)

    // Store incoming report
    try await reportStore.ingestReportMessage(
        message,
        level: level,
        isOutbound: false,
        createdAt: createdAt,
        deliveredAt: processedAt,
        defaultStatus: .pending,
        action: .none
    )

    // Update relationship report count (they reported us)
    if let relationship = relationshipStore.relationship(forGroupId: groupId) {
        try await relationshipStore.incrementRemoteReportCount(relationshipId: relationship.id)
    }

    // Log audit
    try await moderationAuditStore.logAction(
        type: .reportSubmitted,
        actorKey: message.by,
        targetType: "video",
        targetId: message.videoId,
        details: [
            "level": level.rawValue,
            "reason": message.reason,
            "direction": "inbound"
        ]
    )

    // Notify parent about incoming report
    NotificationCenter.default.post(
        name: .incomingReportReceived,
        object: nil,
        userInfo: [
            "reportId": message.reportId ?? UUID().uuidString,
            "level": level.rawValue,
            "videoId": message.videoId
        ]
    )
}
```

---

## 4. Phase 3: Relationship State Management

**Goal**: Integrate relationship state into message flow and UI.

### 4.1 Filter Messages by Relationship State

**File**: `MyTube/Services/Marmot/MarmotProjectionStore.swift`

Add filtering before projection:

```swift
/// Check if messages from this group should be processed
private func shouldProcessMessages(fromGroup groupId: String) -> Bool {
    guard let relationship = relationshipStore.relationship(forGroupId: groupId) else {
        // Unknown group - allow (might be new relationship)
        return true
    }
    return relationship.state.allowsReceiving
}

// In projectMessages(), add check:
func projectMessages(inGroup groupId: String) async throws {
    guard shouldProcessMessages(fromGroup: groupId) else {
        // Relationship is frozen/blocked - skip processing
        return
    }

    // ... existing projection logic
}
```

### 4.2 Create Relationships on Group Creation

**File**: `MyTube/Features/ParentZone/ParentZoneViewModel.swift`

Add relationship creation when accepting welcome or creating group:

```swift
// After successful group creation in inviteParentToGroup():
private func createRelationshipForGroup(
    groupId: String,
    localProfileId: UUID,
    remoteParentKey: String,
    remoteChildKey: String?
) async throws {
    _ = try await appEnvironment.relationshipStore.createRelationship(
        localProfileId: localProfileId,
        remoteParentKey: remoteParentKey,
        remoteChildKey: remoteChildKey,
        mlsGroupId: groupId
    )

    // Log audit
    try await appEnvironment.moderationAuditStore.logAction(
        type: .relationshipCreated,
        actorKey: parentIdentity?.publicKey ?? "",
        targetType: "relationship",
        targetId: groupId,
        details: [
            "remoteParentKey": remoteParentKey,
            "localProfileId": localProfileId.uuidString
        ]
    )
}

// After accepting welcome in handleAcceptedWelcome():
// Call createRelationshipForGroup()
```

### 4.3 Handle Media Deletion on Block

**File**: `MyTube/Services/RemoteVideoStore.swift`

Add notification handler:

```swift
// In init():
NotificationCenter.default.addObserver(
    self,
    selector: #selector(handleRelationshipMediaDeletion),
    name: .relationshipMediaDeletionRequested,
    object: nil
)

@objc private func handleRelationshipMediaDeletion(_ notification: Notification) {
    guard let groupId = notification.userInfo?["mlsGroupId"] as? String else { return }

    Task {
        await deleteMediaForGroup(groupId: groupId)
    }
}

/// Delete all local media for videos from a specific group
func deleteMediaForGroup(groupId: String) async {
    let request = RemoteVideoEntity.fetchRequest()
    request.predicate = NSPredicate(format: "mlsGroupId == %@", groupId)

    do {
        let videos = try context.fetch(request)
        for video in videos {
            // Delete media files
            if let blobURL = video.blobURL {
                try? FileManager.default.removeItem(at: URL(string: blobURL)!)
            }
            if let thumbURL = video.thumbURL {
                try? FileManager.default.removeItem(at: URL(string: thumbURL)!)
            }

            // Update status
            video.status = "blocked"
        }
        try context.save()
    } catch {
        print("Failed to delete media for group \(groupId): \(error)")
    }
}
```

### 4.4 Relationship Management UI

**File**: `MyTube/Features/ParentZone/RelationshipManagementView.swift` (new file)

```swift
import SwiftUI

struct RelationshipManagementView: View {
    @EnvironmentObject var appEnvironment: AppEnvironment
    @State private var showingActionSheet = false
    @State private var selectedRelationship: RelationshipModel?

    let profileId: UUID

    var relationships: [RelationshipModel] {
        appEnvironment.relationshipStore.relationships(forProfile: profileId)
    }

    var body: some View {
        List {
            ForEach(relationships) { relationship in
                RelationshipRow(relationship: relationship)
                    .swipeActions(edge: .trailing) {
                        if relationship.state == .active {
                            Button("Pause") {
                                Task {
                                    try? await freezeRelationship(relationship)
                                }
                            }
                            .tint(.orange)

                            Button("Block") {
                                selectedRelationship = relationship
                                showingActionSheet = true
                            }
                            .tint(.red)
                        } else if relationship.state == .frozen {
                            Button("Resume") {
                                Task {
                                    try? await unfreezeRelationship(relationship)
                                }
                            }
                            .tint(.green)
                        } else if relationship.state == .blocked {
                            Button("Unblock") {
                                Task {
                                    try? await unblockRelationship(relationship)
                                }
                            }
                            .tint(.green)
                        }
                    }
            }
        }
        .navigationTitle("Family Connections")
        .confirmationDialog(
            "Block this family?",
            isPresented: $showingActionSheet,
            presenting: selectedRelationship
        ) { relationship in
            Button("Block", role: .destructive) {
                Task {
                    try? await blockRelationship(relationship)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Their videos will be removed from your device. You can unblock later.")
        }
    }

    private func freezeRelationship(_ r: RelationshipModel) async throws {
        guard let parentKey = appEnvironment.identityStore.parentIdentity?.publicKey else { return }
        try await appEnvironment.relationshipStore.freeze(
            relationshipId: r.id,
            reason: "Paused by parent",
            by: parentKey
        )
    }

    private func unfreezeRelationship(_ r: RelationshipModel) async throws {
        guard let parentKey = appEnvironment.identityStore.parentIdentity?.publicKey else { return }
        try await appEnvironment.relationshipStore.unfreeze(relationshipId: r.id, by: parentKey)
    }

    private func blockRelationship(_ r: RelationshipModel) async throws {
        guard let parentKey = appEnvironment.identityStore.parentIdentity?.publicKey else { return }
        try await appEnvironment.relationshipStore.block(
            relationshipId: r.id,
            reason: "Blocked by parent",
            by: parentKey
        )
    }

    private func unblockRelationship(_ r: RelationshipModel) async throws {
        guard let parentKey = appEnvironment.identityStore.parentIdentity?.publicKey else { return }
        try await appEnvironment.relationshipStore.unblock(relationshipId: r.id, by: parentKey)
    }
}

struct RelationshipRow: View {
    let relationship: RelationshipModel

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(relationship.remoteParentKey.prefix(12) + "...")
                    .font(.headline)

                HStack(spacing: 8) {
                    StatusBadge(state: relationship.state)

                    if relationship.totalReportCount > 0 {
                        Label("\(relationship.totalReportCount)", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer()

            if relationship.blockedByRemote {
                Image(systemName: "nosign")
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }
}

struct StatusBadge: View {
    let state: RelationshipState

    var body: some View {
        Text(state.displayName)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(Capsule())
    }

    var backgroundColor: Color {
        switch state {
        case .active: return .green.opacity(0.2)
        case .frozen: return .orange.opacity(0.2)
        case .blocked: return .red.opacity(0.2)
        case .removed: return .gray.opacity(0.2)
        }
    }

    var foregroundColor: Color {
        switch state {
        case .active: return .green
        case .frozen: return .orange
        case .blocked: return .red
        case .removed: return .gray
        }
    }
}
```

---

## 5. Phase 4: Moderation Infrastructure

**Goal**: Enable Tubestr moderators to act on Level 3 reports.

### 5.1 Moderation Configuration

**File**: `MyTube/Services/Safety/ModerationConfig.swift` (new file)

```swift
import Foundation

/// Configuration for moderation features
enum ModerationConfig {

    /// Relays that receive Level 3 moderation reports
    static let moderationRelays = ["wss://no.str.cr"]

    /// Known Tubestr moderator public keys
    /// These keys can issue moderator actions that clients will respect
    static var moderatorKeys: Set<String> = [
        // Add moderator npubs here
        // "npub1..."
    ]

    /// Check if a public key belongs to a moderator
    static func isModerator(_ pubkey: String) -> Bool {
        moderatorKeys.contains(pubkey)
    }

    /// Nostr kind for moderator action messages
    static let moderatorActionKind = 4550
}
```

### 5.2 Moderator Action Message

**File**: `MyTube/Services/Marmot/MarmotMessageModels.swift`

Add moderator action message type:

```swift
/// Message from Tubestr moderators in response to Level 3 reports
struct ModeratorActionMessage: Codable, Sendable {
    let t: String                    // "mytube/mod_action"
    let reportId: String             // Original report ID
    let videoId: String?             // Target video (if applicable)
    let subjectParentKey: String?    // Target parent (if applicable)
    let action: String               // Action taken
    let reason: String?              // Explanation
    let by: String                   // Moderator npub
    let ts: Double

    enum CodingKeys: String, CodingKey {
        case t, reportId = "report_id", videoId = "video_id"
        case subjectParentKey = "subject_parent_key"
        case action, reason, by, ts
    }
}

/// Actions moderators can take
enum ModeratorAction: String, Codable, Sendable {
    case dismiss = "dismiss"         // Report dismissed, no action
    case warn = "warn"               // Warning issued
    case removeContent = "remove"    // Content removed
    case suspendAccount = "suspend"  // Account suspended
    case banAccount = "ban"          // Account banned
}
```

### 5.3 Handle Incoming Moderator Actions

**File**: `MyTube/Services/Marmot/MarmotProjectionStore.swift`

Add handler for moderator action messages:

```swift
func projectModeratorAction(content: String, from event: NostrEvent) async throws {
    // Verify sender is a known moderator
    guard ModerationConfig.isModerator(event.pubkey) else {
        print("Ignoring mod action from unknown key: \(event.pubkey)")
        return
    }

    let data = Data(content.utf8)
    let message = try decoder.decode(ModeratorActionMessage.self, from: data)

    // Log the moderator action
    try await moderationAuditStore.logAction(
        type: .moderatorAction,
        actorKey: message.by,
        targetType: "report",
        targetId: message.reportId,
        details: [
            "action": message.action,
            "reason": message.reason ?? "",
            "videoId": message.videoId ?? ""
        ]
    )

    // Apply action locally
    switch ModeratorAction(rawValue: message.action) {
    case .removeContent:
        if let videoId = message.videoId {
            try await remoteVideoStore.applyModeratorRemoval(videoId: videoId)
        }

    case .warn:
        // Show warning to parent
        NotificationCenter.default.post(
            name: .moderatorWarningReceived,
            object: nil,
            userInfo: [
                "reason": message.reason ?? "Content policy violation",
                "reportId": message.reportId
            ]
        )

    case .suspendAccount, .banAccount:
        // Handle account-level actions
        NotificationCenter.default.post(
            name: .accountActionReceived,
            object: nil,
            userInfo: [
                "action": message.action,
                "reason": message.reason ?? ""
            ]
        )

    default:
        break
    }

    // Update original report status
    if let reportId = UUID(uuidString: message.reportId) {
        try await reportStore.updateStatus(
            reportId: reportId,
            status: .actioned,
            action: ReportAction(rawValue: message.action) ?? .none
        )
    }
}
```

### 5.4 Subscribe to Moderator Actions

**File**: `MyTube/Services/Sync/SyncCoordinator.swift`

Add subscription for moderator action events:

```swift
// In ensurePrimarySubscription(), add filter:
let moderatorFilter = NostrFilter(
    kinds: [ModerationConfig.moderatorActionKind],
    authors: Array(ModerationConfig.moderatorKeys)
)
filters.append(moderatorFilter)

// In handle(event:), add case:
case ModerationConfig.moderatorActionKind:
    try await marmotProjectionStore.projectModeratorAction(
        content: event.content,
        from: event
    )
```

### 5.5 Notifications for Moderation Events

**File**: `MyTube/Services/Marmot/MarmotNotifications.swift`

Add notification names:

```swift
extension Notification.Name {
    // Existing...

    // Moderation notifications
    static let incomingReportReceived = Notification.Name("incomingReportReceived")
    static let moderatorWarningReceived = Notification.Name("moderatorWarningReceived")
    static let accountActionReceived = Notification.Name("accountActionReceived")
}
```

---

## 6. Phase 5: Content Removal Enhancements

**Goal**: Enhance tombstone and lifecycle handling for moderation.

### 6.1 Add Removal Reason to Tombstones

**File**: `MyTube/Services/Marmot/MarmotShareService.swift`

Enhance tombstone publishing:

```swift
/// Reasons for content removal
enum ContentRemovalReason: String, Codable, Sendable {
    case ownerDeleted = "owner_deleted"
    case parentDeleted = "parent_deleted"
    case policyViolation = "policy_violation"
    case moderatorAction = "moderator_action"
    case autoDetected = "auto_detected"
    case reportActioned = "report_actioned"
}

/// Publish a video tombstone with removal reason
func publishTombstone(
    videoId: String,
    reason: ContentRemovalReason
) async throws {
    guard let parentIdentity = try await identityStore.getParentIdentity() else {
        throw ShareError.noParentIdentity
    }

    let event = NostrEvent(
        kind: MyTubeEventKind.videoTombstone.rawValue,
        content: "",
        tags: [
            ["d", "mytube/video:\(videoId)"],
            ["reason", reason.rawValue],
            ["deleted_at", String(Int(Date().timeIntervalSince1970))]
        ],
        pubkey: parentIdentity.publicKey
    )

    let signedEvent = try await signEvent(event)
    try await marmotTransport.publish(event: signedEvent)
}
```

### 6.2 Enhanced Tombstone Processing

**File**: `MyTube/Services/Sync/NostrEventReducer.swift`

Update tombstone handler to capture reason:

```swift
func reduceVideoTombstone(_ event: NostrEvent) async throws {
    guard let dTag = event.tags.first(where: { $0.first == "d" })?[safe: 1],
          dTag.hasPrefix("mytube/video:") else {
        return
    }

    let videoId = String(dTag.dropFirst("mytube/video:".count))
    let reason = event.tags.first(where: { $0.first == "reason" })?[safe: 1]

    // Update video status
    try await remoteVideoStore.applyTombstone(
        videoId: videoId,
        reason: ContentRemovalReason(rawValue: reason ?? "") ?? .ownerDeleted,
        tombstoneDate: event.createdDate
    )

    // Log audit
    try await moderationAuditStore.logAction(
        type: .videoRemoved,
        actorKey: event.pubkey,
        targetType: "video",
        targetId: videoId,
        details: [
            "reason": reason ?? "unknown",
            "tombstoneId": event.id
        ]
    )
}
```

### 6.3 RemoteVideoStore Tombstone Handling

**File**: `MyTube/Services/RemoteVideoStore.swift`

Add enhanced tombstone method:

```swift
/// Apply a tombstone to a video
func applyTombstone(
    videoId: String,
    reason: ContentRemovalReason,
    tombstoneDate: Date
) async throws {
    let request = RemoteVideoEntity.fetchRequest()
    request.predicate = NSPredicate(format: "videoId == %@", videoId)
    request.fetchLimit = 1

    guard let video = try context.fetch(request).first else {
        return // Video not found locally
    }

    // Delete media files
    deleteMediaFiles(for: video)

    // Update status
    video.status = "tombstoned"
    video.lastSyncedAt = tombstoneDate

    // Store removal reason in a new field or existing metadata
    // video.removalReason = reason.rawValue

    try context.save()

    // Notify UI
    NotificationCenter.default.post(
        name: .videoTombstoned,
        object: nil,
        userInfo: [
            "videoId": videoId,
            "reason": reason.rawValue
        ]
    )
}

/// Apply moderator-initiated removal
func applyModeratorRemoval(videoId: String) async throws {
    try await applyTombstone(
        videoId: videoId,
        reason: .moderatorAction,
        tombstoneDate: Date()
    )
}

private func deleteMediaFiles(for video: RemoteVideoEntity) {
    if let blobURL = video.blobURL, let url = URL(string: blobURL) {
        try? FileManager.default.removeItem(at: url)
    }
    if let thumbURL = video.thumbURL, let url = URL(string: thumbURL) {
        try? FileManager.default.removeItem(at: url)
    }
}
```

---

## 7. Testing Strategy

### 7.1 Unit Tests

**File**: `MyTubeTests/RelationshipStoreTests.swift` (new file)

```swift
import XCTest
@testable import MyTube

final class RelationshipStoreTests: XCTestCase {
    var store: RelationshipStore!
    var persistenceController: PersistenceController!

    override func setUp() async throws {
        persistenceController = PersistenceController(inMemory: true)
        store = await RelationshipStore(persistenceController: persistenceController)
    }

    func testCreateRelationship() async throws {
        let relationship = try await store.createRelationship(
            localProfileId: UUID(),
            remoteParentKey: "npub1test",
            remoteChildKey: nil,
            mlsGroupId: "group123"
        )

        XCTAssertEqual(relationship.state, .active)
        XCTAssertEqual(relationship.localReportCount, 0)
    }

    func testStateTransitions() async throws {
        let relationship = try await store.createRelationship(
            localProfileId: UUID(),
            remoteParentKey: "npub1test",
            remoteChildKey: nil,
            mlsGroupId: "group123"
        )

        // Active -> Frozen: valid
        try await store.freeze(relationshipId: relationship.id, reason: "Test", by: "npub1actor")
        let frozen = store.relationships.first { $0.id == relationship.id }
        XCTAssertEqual(frozen?.state, .frozen)

        // Frozen -> Active: valid
        try await store.unfreeze(relationshipId: relationship.id, by: "npub1actor")
        let active = store.relationships.first { $0.id == relationship.id }
        XCTAssertEqual(active?.state, .active)
    }

    func testInvalidTransition() async throws {
        let relationship = try await store.createRelationship(
            localProfileId: UUID(),
            remoteParentKey: "npub1test",
            remoteChildKey: nil,
            mlsGroupId: "group123"
        )

        // Remove relationship
        try await store.remove(relationshipId: relationship.id, reason: "Test", by: "npub1actor")

        // Removed -> Active: invalid
        do {
            try await store.unfreeze(relationshipId: relationship.id, by: "npub1actor")
            XCTFail("Should have thrown")
        } catch RelationshipError.invalidTransition {
            // Expected
        }
    }
}
```

**File**: `MyTubeTests/ReportLevelRoutingTests.swift` (new file)

```swift
import XCTest
@testable import MyTube

final class ReportLevelRoutingTests: XCTestCase {

    func testReportLevelRecipientTypes() {
        XCTAssertEqual(ReportLevel.peer.recipientType, "group")
        XCTAssertEqual(ReportLevel.parent.recipientType, "parents")
        XCTAssertEqual(ReportLevel.moderator.recipientType, "moderators")
    }

    func testReportMessageEncoding() throws {
        let message = ReportMessage(
            t: "mytube/report",
            videoId: "video123",
            subjectChild: "child456",
            reason: "inappropriate",
            note: "Test note",
            by: "npub1reporter",
            ts: 1700000000,
            level: 2,
            recipientType: "parents",
            reporterChild: "child789",
            reportId: "report-uuid"
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(message)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["level"] as? Int, 2)
        XCTAssertEqual(json["recipient_type"] as? String, "parents")
        XCTAssertEqual(json["reporter_child"] as? String, "child789")
    }

    func testBackwardCompatibility() throws {
        // Old message without level field
        let oldJson = """
        {
            "t": "mytube/report",
            "video_id": "video123",
            "subject_child": "child456",
            "reason": "spam",
            "by": "npub1old",
            "ts": 1700000000
        }
        """

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let message = try decoder.decode(ReportMessage.self, from: oldJson.data(using: .utf8)!)

        // Should default to level 1
        XCTAssertEqual(message.resolvedLevel, 1)
        XCTAssertNil(message.level)
    }
}
```

### 7.2 Integration Tests

Test full flow from report submission to reception:

1. Submit Level 1 report → verify published to group
2. Submit Level 2 report → verify both parents notified
3. Submit Level 3 report → verify sent to moderation relay
4. Block relationship → verify media deleted
5. Receive moderator action → verify applied locally

---

## 8. File Reference

### Files to Modify

| File | Phase | Changes |
|------|-------|---------|
| `MarmotMessageModels.swift` | 1, 4 | Extend ReportMessage, add ModeratorActionMessage |
| `ReportModels.swift` | 1 | Add ReportLevel enum |
| `MyTube.xcdatamodel` | 1 | Add entities and fields |
| `AppEnvironment.swift` | 1 | Add new stores |
| `ReportCoordinator.swift` | 2 | Level-based routing |
| `MarmotTransport.swift` | 2 | Moderation relay publishing |
| `ReportAbuseSheet.swift` | 2 | Level picker UI |
| `MarmotProjectionStore.swift` | 2, 3, 4 | Report/moderator projection |
| `RemoteVideoStore.swift` | 3, 5 | Media deletion, tombstones |
| `ParentZoneViewModel.swift` | 3 | Relationship creation |
| `SyncCoordinator.swift` | 4 | Moderator action subscription |
| `NostrEventReducer.swift` | 5 | Enhanced tombstone handling |
| `MarmotShareService.swift` | 5 | Tombstone with reason |
| `MarmotNotifications.swift` | 2, 4 | New notification names |

### New Files to Create

| File | Phase | Purpose |
|------|-------|---------|
| `RelationshipModels.swift` | 1 | State enum, model struct |
| `RelationshipStore.swift` | 1 | Relationship CRUD |
| `ModerationAuditStore.swift` | 1 | Audit trail |
| `ModerationConfig.swift` | 4 | Moderator keys, relays |
| `RelationshipManagementView.swift` | 3 | Parent UI for relationships |
| `RelationshipStoreTests.swift` | 1 | Unit tests |
| `ReportLevelRoutingTests.swift` | 2 | Unit tests |

---

## Implementation Notes

1. **Backward Compatibility**: New fields on `ReportMessage` are optional to maintain compatibility with existing messages.

2. **Core Data Migration**: Adding new entities and fields requires a lightweight migration. Ensure the data model version is incremented.

3. **Audit Trail**: Every state change should be logged via `ModerationAuditStore` for accountability.

4. **Media Deletion**: When blocking a relationship, all local media is deleted immediately. This is irreversible.

5. **Moderator Keys**: The initial moderator key set will be empty. Add Tubestr moderator npubs to `ModerationConfig.moderatorKeys` before deploying Level 3 functionality.

6. **Testing**: Each phase should be fully tested before proceeding to the next. Focus on state transitions and message routing.
