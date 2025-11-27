//
//  LikePublisher.swift
//  MyTube
//
//  Created by Assistant on 11/2/25.
//

import Foundation
import OSLog

enum LikePublisherError: Error {
    case missingChildProfile
    case missingVideoOwner
    case rateLimitExceeded
    case parentIdentityMissing
    case groupUnavailable
}

/// Publishes like events to Nostr
actor LikePublisher {
    private let marmotShareService: MarmotShareService
    private let keyStore: KeychainKeyStore
    private let remoteVideoStore: RemoteVideoStore
    private let logger = Logger(subsystem: "com.mytube", category: "LikePublisher")

    // Rate limiting: 120 likes per hour per child
    private var rateLimitTracker: [String: [Date]] = [:]
    private let maxLikesPerHour = 120

    init(
        marmotShareService: MarmotShareService,
        keyStore: KeychainKeyStore,
        remoteVideoStore: RemoteVideoStore
    ) {
        self.marmotShareService = marmotShareService
        self.keyStore = keyStore
        self.remoteVideoStore = remoteVideoStore
    }
    
    /// Publish a like for a video
    func publishLike(
        videoId: UUID,
        viewerChildNpub: String
    ) async throws {
        // Check rate limit
        try await checkRateLimit(for: viewerChildNpub)

        // Get the video to find its group
        guard let video = try remoteVideoStore.fetchVideo(videoId: videoId.uuidString) else {
            throw LikePublisherError.missingVideoOwner
        }

        guard let groupId = video.mlsGroupId else {
            throw LikePublisherError.groupUnavailable
        }

        // Get parent key
        guard let parentKeyPair = try keyStore.fetchKeyPair(role: .parent) else {
            throw LikePublisherError.parentIdentityMissing
        }

        // Create like message
        let message = LikeMessage(
            videoId: videoId.uuidString,
            viewerChild: viewerChildNpub,
            by: parentKeyPair.publicKeyHex,
            timestamp: Date()
        )

        try await marmotShareService.publishLike(
            message: message,
            mlsGroupId: groupId
        )

        // Track for rate limiting
        await recordLikeForRateLimit(childNpub: viewerChildNpub)

        logger.info("Published like for video \(videoId) from \(viewerChildNpub.prefix(8))…")
    }
    
    /// Publish an unlike (like removal) - this could be a separate message type in the future
    func publishUnlike(
        videoId: UUID,
        viewerChildNpub: String
    ) async throws {
        // For MVP, we don't send unlike messages to Nostr
        // The like is just removed locally
        logger.info("Unlike recorded locally for video \(videoId) from \(viewerChildNpub.prefix(8))…")
    }

    private func checkRateLimit(for childNpub: String) async throws {
        let now = Date()
        let oneHourAgo = now.addingTimeInterval(-3600)
        
        // Get existing likes in the past hour
        var recentLikes = rateLimitTracker[childNpub] ?? []
        
        // Remove likes older than one hour
        recentLikes = recentLikes.filter { $0 > oneHourAgo }
        
        // Check if limit exceeded
        if recentLikes.count >= maxLikesPerHour {
            logger.warning("Rate limit exceeded for child \(childNpub.prefix(8))…")
            throw LikePublisherError.rateLimitExceeded
        }
        
        // Update tracker
        rateLimitTracker[childNpub] = recentLikes
    }
    
    private func recordLikeForRateLimit(childNpub: String) async {
        var recentLikes = rateLimitTracker[childNpub] ?? []
        recentLikes.append(Date())
        rateLimitTracker[childNpub] = recentLikes
    }
}

extension LikePublisherError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingChildProfile:
            return "Child profile not found"
        case .missingVideoOwner:
            return "Video owner information not found"
        case .parentIdentityMissing:
            return "Parent identity missing. Complete setup before liking videos."
        case .groupUnavailable:
            return "This family connection is not ready for likes yet."
        case .rateLimitExceeded:
            return "Too many likes. Please try again later."
        }
    }
}
