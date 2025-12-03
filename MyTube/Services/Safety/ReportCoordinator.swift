//
//  ReportCoordinator.swift
//  MyTube
//
//  Created by Assistant on 02/15/26.
//

import Foundation
import OSLog

actor ReportCoordinator {
    enum ReportCoordinatorError: Error {
        case parentIdentityMissing
        case subjectUnknown
        case groupNotFound
    }

    private let reportStore: ReportStore
    private let remoteVideoStore: RemoteVideoStore
    private let marmotShareService: MarmotShareService
    private let marmotTransport: MarmotTransport
    private let keyStore: KeychainKeyStore
    private let storagePaths: StoragePaths
    private let groupMembershipCoordinator: any GroupMembershipCoordinating
    private let relationshipStore: RelationshipStore
    private let moderationAuditStore: ModerationAuditStore
    private let logger = Logger(subsystem: "com.mytube", category: "ReportCoordinator")

    init(
        reportStore: ReportStore,
        remoteVideoStore: RemoteVideoStore,
        marmotShareService: MarmotShareService,
        marmotTransport: MarmotTransport,
        keyStore: KeychainKeyStore,
        storagePaths: StoragePaths,
        groupMembershipCoordinator: any GroupMembershipCoordinating,
        relationshipStore: RelationshipStore,
        moderationAuditStore: ModerationAuditStore
    ) {
        self.reportStore = reportStore
        self.remoteVideoStore = remoteVideoStore
        self.marmotShareService = marmotShareService
        self.marmotTransport = marmotTransport
        self.keyStore = keyStore
        self.storagePaths = storagePaths
        self.groupMembershipCoordinator = groupMembershipCoordinator
        self.relationshipStore = relationshipStore
        self.moderationAuditStore = moderationAuditStore
    }

    /// Submit a report with level-based routing (legacy method for backward compatibility)
    @discardableResult
    func submitReport(
        videoId: String,
        subjectChild: String,
        reason: ReportReason,
        note: String?,
        action: ReportAction,
        createdAt: Date = Date()
    ) async throws -> ReportModel {
        // Default to Level 1 (peer) for backward compatibility
        try await submitReport(
            videoId: videoId,
            subjectChild: subjectChild,
            reason: reason,
            note: note,
            level: .peer,
            reporterChild: nil,
            action: action,
            createdAt: createdAt
        )
    }

    /// Submit a report with level-based routing
    @discardableResult
    func submitReport(
        videoId: String,
        subjectChild: String,
        reason: ReportReason,
        note: String?,
        level: ReportLevel,
        reporterChild: String?,
        action: ReportAction,
        createdAt: Date = Date()
    ) async throws -> ReportModel {
        guard let parentPair = try keyStore.fetchKeyPair(role: .parent) else {
            throw ReportCoordinatorError.parentIdentityMissing
        }

        let reporterKey = parentPair.publicKeyBech32 ?? parentPair.publicKeyHex
        let reportId = UUID()
        let message = ReportMessage(
            videoId: videoId,
            subjectChild: subjectChild,
            reason: reason.rawValue,
            note: note,
            by: reporterKey,
            timestamp: createdAt,
            level: level.rawValue,
            recipientType: level.recipientType,
            reporterChild: reporterChild,
            reportId: reportId.uuidString
        )

        // Store report locally first
        let stored = try await reportStore.ingestReportMessage(
            message,
            level: level,
            isOutbound: true,
            createdAt: createdAt,
            action: action
        )

        // Log audit entry
        try? await moderationAuditStore.logAction(
            type: .reportSubmitted,
            actorKey: reporterKey,
            targetType: "video",
            targetId: videoId,
            details: [
                "level": String(level.rawValue),
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
            try await applyReportAction(action, videoId: videoId, reason: reason, createdAt: createdAt)
        }

        // Update relationship report count
        if let groupId = resolveGroupId(forVideoId: videoId),
           let relationship = await relationshipStore.relationship(forGroupId: groupId) {
            try? await relationshipStore.incrementLocalReportCount(relationshipId: relationship.id)
        }

        let finalAction: ReportAction = action == .none ? .reportOnly : action
        try? await reportStore.updateStatus(
            reportId: stored.id,
            status: .actioned,
            action: finalAction,
            lastActionAt: createdAt
        )

        await applyRelationshipAction(
            action: finalAction,
            subjectChild: subjectChild,
            timestamp: createdAt
        )

        return stored
    }

    // MARK: - Level-based Publishing

    /// Level 1: Publish to the originating MLS group
    private func publishToGroup(message: ReportMessage, videoId: String) async throws {
        guard let groupId = resolveGroupId(forVideoId: videoId) else {
            throw ReportCoordinatorError.groupNotFound
        }
        try await marmotShareService.publishReport(message: message, mlsGroupId: groupId)
        logger.info("Published Level 1 report to group \(groupId.prefix(16), privacy: .public)")
    }

    /// Level 2: Publish to group so both parents see it
    private func publishToParents(message: ReportMessage, videoId: String) async throws {
        // Level 2 reports are still published to the group, but marked as parent-level
        // Both parents in the group can see and respond
        guard let groupId = resolveGroupId(forVideoId: videoId) else {
            throw ReportCoordinatorError.groupNotFound
        }
        try await marmotShareService.publishReport(message: message, mlsGroupId: groupId)
        logger.info("Published Level 2 (parent) report to group \(groupId.prefix(16), privacy: .public)")
    }

    /// Level 3: Publish to moderation relays
    private func publishToModerators(message: ReportMessage) async throws {
        try await marmotTransport.publishToModerationRelays(message: message)
        logger.info("Published Level 3 report to moderation relays for video \(message.videoId, privacy: .public)")
    }

    private func resolveGroupId(forVideoId videoId: String) -> String? {
        guard let video = try? remoteVideoStore.fetchVideo(videoId: videoId) else {
            return nil
        }
        return video.mlsGroupId
    }

    private func applyReportAction(
        _ action: ReportAction,
        videoId: String,
        reason: ReportReason,
        createdAt: Date
    ) async throws {
        guard action == .block || action == .deleted else { return }

        do {
            _ = try remoteVideoStore.markVideoAsBlocked(
                videoId: videoId,
                reason: reason.rawValue,
                storagePaths: storagePaths,
                timestamp: createdAt
            )
        } catch {
            logger.error("Failed to mark remote video \(videoId, privacy: .public) as blocked: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Legacy helpers

    private func resolveRecipientGroups(
        videoId: String,
        subjectChild: String
    ) -> [String] {
        guard let video = try? remoteVideoStore.fetchVideo(videoId: videoId),
              let groupId = video.mlsGroupId else {
            return []
        }
        return [groupId]
    }

    private func applyRelationshipAction(
        action: ReportAction,
        subjectChild: String,
        timestamp: Date
    ) async {
        guard action == .unfollow || action == .block else { return }
        guard let parentPair = try? keyStore.fetchKeyPair(role: .parent) else {
            logger.info("Skipping follow action; parent identity missing.")
            return
        }

        let actorKey = parentPair.publicKeyBech32 ?? parentPair.publicKeyHex
        logger.info("Relationship action \(action.rawValue) for \(subjectChild) - would remove from groups")
    }
}
