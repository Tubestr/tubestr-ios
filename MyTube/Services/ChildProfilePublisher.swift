//
//  ChildProfilePublisher.swift
//  MyTube
//
//  Created by Codex on 12/24/25.
//

import Foundation
import OSLog
import NostrSDK

enum ChildProfilePublisherError: Error {
    case childIdentityMissing
    case parentIdentityMissing
    case relaysUnavailable
    case encodingFailed
}

actor ChildProfilePublisher {
    private let identityManager: IdentityManager
    private let childProfileStore: ChildProfileStore
    private let nostrClient: NostrClient
    private let relayDirectory: RelayDirectory
    private let signer: NostrEventSigner
    private let logger = Logger(subsystem: "com.mytube", category: "ChildProfilePublisher")
    private let encoder: JSONEncoder
    private let publishTimeoutNanoseconds: UInt64 = 10 * NSEC_PER_SEC

    init(
        identityManager: IdentityManager,
        childProfileStore: ChildProfileStore,
        nostrClient: NostrClient,
        relayDirectory: RelayDirectory,
        signer: NostrEventSigner = NostrEventSigner()
    ) {
        self.identityManager = identityManager
        self.childProfileStore = childProfileStore
        self.nostrClient = nostrClient
        self.relayDirectory = relayDirectory
        self.signer = signer

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
    }

    /// Publishes kind 0 metadata for a child using the child's own Nostr keypair.
    /// The metadata includes `mytube_parent` linking to the parent's npub.
    @discardableResult
    func publishProfile(
        for profile: ProfileModel,
        identity: ChildIdentity? = nil,
        nameOverride: String? = nil,
        displayNameOverride: String? = nil,
        about: String? = nil,
        pictureURL: String? = nil,
        createdAt: Date = Date()
    ) async throws -> ChildProfileModel {
        // Get the child identity (with keypair)
        let childIdentity: ChildIdentity
        if let provided = identity {
            childIdentity = provided
        } else if let existing = identityManager.childIdentity(for: profile) {
            childIdentity = existing
        } else {
            throw ChildProfilePublisherError.childIdentityMissing
        }

        // Get the parent identity for the mytube_parent reference
        guard let parentIdentity = try identityManager.parentIdentity(),
              let parentNpub = parentIdentity.publicKeyBech32 else {
            throw ChildProfilePublisherError.parentIdentityMissing
        }

        let baseName = nameOverride ?? profile.name

        // Build the minimal kind 0 payload with mytube_parent reference
        var payload = ProfileMetadataPayload()
        payload.name = baseName
        payload.displayName = displayNameOverride ?? baseName
        payload.about = about
        payload.picture = pictureURL
        payload.mytubeParent = parentNpub

        let contentData: Data
        do {
            contentData = try encoder.encode(payload)
        } catch {
            throw ChildProfilePublisherError.encodingFailed
        }
        guard let content = String(data: contentData, encoding: .utf8) else {
            throw ChildProfilePublisherError.encodingFailed
        }

        // Sign with the child's own keypair
        let event = try signer.makeEvent(
            kind: .metadata,
            tags: [],
            content: content,
            keyPair: childIdentity.keyPair,
            createdAt: createdAt
        )

        // Publish to relays
        let relays = await relayDirectory.currentRelayURLs()
        guard !relays.isEmpty else {
            throw ChildProfilePublisherError.relaysUnavailable
        }

        let connectedRelaySet = Set(
            (await nostrClient.relayStatuses())
                .filter { $0.status == .connected }
                .map(\.url)
        )
        let targetRelays = relays.filter { connectedRelaySet.contains($0) }
        guard !targetRelays.isEmpty else {
            throw ChildProfilePublisherError.relaysUnavailable
        }

        try await publish(event: event, to: targetRelays)
        logger.info("Published child metadata event \(event.idHex, privacy: .public) for \(profile.name, privacy: .public)")

        // Store locally as well
        let childPubkeyHex = childIdentity.publicKeyHex.lowercased()
        return try childProfileStore.upsertProfile(
            publicKey: childPubkeyHex,
            name: baseName,
            displayName: displayNameOverride ?? baseName,
            about: about,
            pictureURLString: pictureURL,
            updatedAt: createdAt
        )
    }

    private func publish(event: NostrEvent, to relays: [URL]) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await self.nostrClient.publish(event: event, to: relays)
            }

            group.addTask {
                try await Task.sleep(nanoseconds: self.publishTimeoutNanoseconds)
                throw ChildProfilePublisherError.relaysUnavailable
            }

            defer { group.cancelAll() }
            _ = try await group.next()
        }
    }
}
