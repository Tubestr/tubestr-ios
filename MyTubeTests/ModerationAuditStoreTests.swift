import XCTest
@testable import MyTube

final class ModerationAuditStoreTests: XCTestCase {

    @MainActor
    func testLogAction() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ModerationAuditStore(persistence: persistence)

        try await store.logAction(
            type: .reportSubmitted,
            actorKey: "npub1actor",
            targetType: "video",
            targetId: "video-123",
            details: ["reason": "inappropriate", "level": "1"]
        )

        let entries = try await store.recentAuditTrail(limit: 10)
        XCTAssertEqual(entries.count, 1)

        let entry = entries[0]
        XCTAssertEqual(entry.actionType, .reportSubmitted)
        XCTAssertEqual(entry.actorKey, "npub1actor")
        XCTAssertEqual(entry.targetType, "video")
        XCTAssertEqual(entry.targetId, "video-123")
        XCTAssertNotNil(entry.details)
        XCTAssertEqual(entry.details?["reason"], "inappropriate")
    }

    @MainActor
    func testAuditTrailByTarget() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ModerationAuditStore(persistence: persistence)

        let videoId = "video-\(UUID().uuidString)"

        // Log multiple actions for the same video
        try await store.logAction(
            type: .reportSubmitted,
            actorKey: "npub1actor1",
            targetType: "video",
            targetId: videoId
        )

        try await store.logAction(
            type: .videoBlocked,
            actorKey: "npub1actor2",
            targetType: "video",
            targetId: videoId
        )

        // Log action for different video
        try await store.logAction(
            type: .reportSubmitted,
            actorKey: "npub1actor3",
            targetType: "video",
            targetId: "different-video"
        )

        let entries = try await store.auditTrail(forVideoId: videoId)
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.allSatisfy { $0.targetId == videoId })
    }

    @MainActor
    func testAuditTrailByActionType() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ModerationAuditStore(persistence: persistence)

        try await store.logAction(
            type: .reportSubmitted,
            actorKey: "npub1actor1"
        )

        try await store.logAction(
            type: .relationshipBlocked,
            actorKey: "npub1actor2"
        )

        try await store.logAction(
            type: .reportSubmitted,
            actorKey: "npub1actor3"
        )

        let reportEntries = try await store.auditTrail(forActionType: .reportSubmitted)
        XCTAssertEqual(reportEntries.count, 2)
        XCTAssertTrue(reportEntries.allSatisfy { $0.actionType == .reportSubmitted })
    }

    @MainActor
    func testPruneOldEntries() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ModerationAuditStore(persistence: persistence)

        // Log some entries
        try await store.logAction(type: .reportSubmitted, actorKey: "npub1actor1")
        try await store.logAction(type: .reportSubmitted, actorKey: "npub1actor2")
        try await store.logAction(type: .reportSubmitted, actorKey: "npub1actor3")

        // Prune entries older than tomorrow (should delete all)
        let tomorrow = Date().addingTimeInterval(86400)
        let deletedCount = try await store.pruneOldEntries(olderThan: tomorrow)

        XCTAssertEqual(deletedCount, 3)

        let remaining = try await store.recentAuditTrail()
        XCTAssertEqual(remaining.count, 0)
    }

    @MainActor
    func testModerationActionTypes() {
        // Verify all action types are properly defined
        XCTAssertEqual(ModerationActionType.reportSubmitted.rawValue, "report_submitted")
        XCTAssertEqual(ModerationActionType.relationshipBlocked.rawValue, "relationship_blocked")
        XCTAssertEqual(ModerationActionType.videoBlocked.rawValue, "video_blocked")
        XCTAssertEqual(ModerationActionType.moderatorWarning.rawValue, "moderator_warning")
    }
}
