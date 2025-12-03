import XCTest
@testable import MyTube

final class RelationshipStoreTests: XCTestCase {

    @MainActor
    func testCreateRelationship() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = RelationshipStore(persistence: persistence)

        let localProfileId = UUID()
        let remoteParentKey = "npub1remoteparent"
        let mlsGroupId = UUID().uuidString

        let relationship = try await store.createRelationship(
            localProfileId: localProfileId,
            remoteParentKey: remoteParentKey,
            remoteChildKey: nil,
            mlsGroupId: mlsGroupId
        )

        XCTAssertEqual(relationship.localProfileId, localProfileId)
        XCTAssertEqual(relationship.remoteParentKey, remoteParentKey)
        XCTAssertEqual(relationship.mlsGroupId, mlsGroupId)
        XCTAssertEqual(relationship.state, .active)
        XCTAssertEqual(relationship.localReportCount, 0)
        XCTAssertEqual(relationship.remoteReportCount, 0)
        XCTAssertFalse(relationship.blockedByRemote)
    }

    @MainActor
    func testRelationshipStateTransitions() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = RelationshipStore(persistence: persistence)

        let relationship = try await store.createRelationship(
            localProfileId: UUID(),
            remoteParentKey: "npub1test",
            remoteChildKey: nil,
            mlsGroupId: UUID().uuidString
        )

        // Test freeze transition
        try await store.freeze(
            relationshipId: relationship.id,
            reason: "Temporary pause",
            by: "parent"
        )

        await store.refresh()
        guard let frozen = store.relationships.first(where: { $0.id == relationship.id }) else {
            XCTFail("Relationship not found")
            return
        }
        XCTAssertEqual(frozen.state, .frozen)
        XCTAssertEqual(frozen.stateReason, "Temporary pause")

        // Test unfreeze transition
        try await store.unfreeze(relationshipId: relationship.id, by: "parent")

        await store.refresh()
        guard let unfrozen = store.relationships.first(where: { $0.id == relationship.id }) else {
            XCTFail("Relationship not found")
            return
        }
        XCTAssertEqual(unfrozen.state, .active)
    }

    @MainActor
    func testInvalidStateTransitionThrows() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = RelationshipStore(persistence: persistence)

        let relationship = try await store.createRelationship(
            localProfileId: UUID(),
            remoteParentKey: "npub1test",
            remoteChildKey: nil,
            mlsGroupId: UUID().uuidString
        )

        // Remove the relationship
        try await store.remove(
            relationshipId: relationship.id,
            reason: "Test removal",
            by: "parent"
        )

        // Try to transition from removed (should fail)
        do {
            try await store.unfreeze(relationshipId: relationship.id, by: "parent")
            XCTFail("Should have thrown error for invalid transition")
        } catch let error as RelationshipError {
            if case .invalidTransition(let from, let to) = error {
                XCTAssertEqual(from, .removed)
                XCTAssertEqual(to, .active)
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }

    @MainActor
    func testRelationshipReportCounting() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = RelationshipStore(persistence: persistence)

        let relationship = try await store.createRelationship(
            localProfileId: UUID(),
            remoteParentKey: "npub1test",
            remoteChildKey: nil,
            mlsGroupId: UUID().uuidString
        )

        try await store.incrementLocalReportCount(relationshipId: relationship.id)
        try await store.incrementLocalReportCount(relationshipId: relationship.id)
        try await store.incrementRemoteReportCount(relationshipId: relationship.id)

        await store.refresh()
        guard let updated = store.relationships.first(where: { $0.id == relationship.id }) else {
            XCTFail("Relationship not found")
            return
        }

        XCTAssertEqual(updated.localReportCount, 2)
        XCTAssertEqual(updated.remoteReportCount, 1)
        XCTAssertEqual(updated.totalReportCount, 3)
        XCTAssertFalse(updated.isHealthy)
    }

    @MainActor
    func testRelationshipStateValidTransitions() {
        // Test active state transitions
        XCTAssertTrue(RelationshipState.active.canTransition(to: .frozen))
        XCTAssertTrue(RelationshipState.active.canTransition(to: .blocked))
        XCTAssertTrue(RelationshipState.active.canTransition(to: .removed))
        XCTAssertFalse(RelationshipState.active.canTransition(to: .active))

        // Test frozen state transitions
        XCTAssertTrue(RelationshipState.frozen.canTransition(to: .active))
        XCTAssertTrue(RelationshipState.frozen.canTransition(to: .blocked))
        XCTAssertTrue(RelationshipState.frozen.canTransition(to: .removed))
        XCTAssertFalse(RelationshipState.frozen.canTransition(to: .frozen))

        // Test blocked state transitions
        XCTAssertTrue(RelationshipState.blocked.canTransition(to: .active))
        XCTAssertTrue(RelationshipState.blocked.canTransition(to: .removed))
        XCTAssertFalse(RelationshipState.blocked.canTransition(to: .frozen))

        // Test removed state (terminal)
        XCTAssertFalse(RelationshipState.removed.canTransition(to: .active))
        XCTAssertFalse(RelationshipState.removed.canTransition(to: .frozen))
        XCTAssertFalse(RelationshipState.removed.canTransition(to: .blocked))
    }
}
