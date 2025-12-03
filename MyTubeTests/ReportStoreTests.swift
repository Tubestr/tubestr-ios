import XCTest
@testable import MyTube

final class ReportStoreTests: XCTestCase {
    @MainActor
    func testIngestReportStoresOutboundReport() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ReportStore(persistence: persistence)
        let now = Date()

        let message = ReportMessage(
            videoId: UUID().uuidString,
            subjectChild: "npubsubjectkey",
            reason: ReportReason.inappropriate.rawValue,
            note: "Inappropriate content",
            by: "npubreporter",
            timestamp: now
        )

        let stored = try await store.ingestReportMessage(
            message,
            isOutbound: true,
            createdAt: now,
            action: .reportOnly
        )

        await store.refresh()

        let reports = store.allReports()
        XCTAssertTrue(reports.contains(where: { $0.id == stored.id }))
        XCTAssertTrue(stored.isOutbound)
        XCTAssertEqual(stored.reason, .inappropriate)
    }

    // MARK: - Level Tests

    @MainActor
    func testIngestReportWithLevelOneDefault() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ReportStore(persistence: persistence)
        let now = Date()

        let message = ReportMessage(
            videoId: UUID().uuidString,
            subjectChild: "npubsubjectkey",
            reason: ReportReason.harassment.rawValue,
            note: "Test report",
            by: "npubreporter",
            timestamp: now
        )

        let stored = try await store.ingestReportMessage(
            message,
            isOutbound: true,
            createdAt: now,
            action: .reportOnly
        )

        XCTAssertEqual(stored.level, .peer)
        XCTAssertEqual(stored.recipientType, "group")
    }

    @MainActor
    func testIngestReportWithExplicitLevel() async throws {
        let persistence = PersistenceController(inMemory: true)
        let store = ReportStore(persistence: persistence)
        let now = Date()

        let message = ReportMessage(
            videoId: UUID().uuidString,
            subjectChild: "npubsubjectkey",
            reason: ReportReason.illegal.rawValue,
            note: "Serious concern",
            by: "npubreporter",
            timestamp: now,
            level: 3,
            recipientType: "moderators",
            reporterChild: "child-profile-id"
        )

        let stored = try await store.ingestReportMessage(
            message,
            level: .moderator,
            isOutbound: true,
            createdAt: now,
            action: .reportOnly
        )

        XCTAssertEqual(stored.level, .moderator)
        XCTAssertEqual(stored.recipientType, "moderators")
        XCTAssertEqual(stored.reporterChild, "child-profile-id")
    }

    @MainActor
    func testReportLevelTransitionsAreValid() {
        XCTAssertEqual(ReportLevel.peer.rawValue, 1)
        XCTAssertEqual(ReportLevel.parent.rawValue, 2)
        XCTAssertEqual(ReportLevel.moderator.rawValue, 3)

        XCTAssertEqual(ReportLevel.peer.displayName, "Tell Them")
        XCTAssertEqual(ReportLevel.parent.displayName, "Ask Parents")
        XCTAssertEqual(ReportLevel.moderator.displayName, "Report to Tubestr")
    }
}
