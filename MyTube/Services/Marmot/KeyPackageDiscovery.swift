//
//  KeyPackageDiscovery.swift
//  MyTube
//
//  Created by Assistant on 11/26/25.
//

import Foundation
import NostrSDK
import OSLog

/// Service for discovering and publishing key packages over Nostr relays.
/// This enables key exchange without requiring invitation links - parties can
/// discover each other's key packages by npub alone.
actor KeyPackageDiscovery {
    enum DiscoveryError: Error, LocalizedError {
        case invalidPublicKey(String)
        case noRelaysConnected
        case fetchTimeout
        case noKeyPackagesFound(String)

        var errorDescription: String? {
            switch self {
            case .invalidPublicKey(let key):
                return "Invalid public key: \(key)"
            case .noRelaysConnected:
                return "No relays are connected"
            case .fetchTimeout:
                return "Timed out waiting for key packages"
            case .noKeyPackagesFound(let npub):
                return "No key packages found for \(npub)"
            }
        }
    }

    private let nostrClient: NostrClient
    private let relayDirectory: RelayDirectory
    private let logger = Logger(subsystem: "com.mytube", category: "KeyPackageDiscovery")

    init(nostrClient: NostrClient, relayDirectory: RelayDirectory) {
        self.nostrClient = nostrClient
        self.relayDirectory = relayDirectory
    }

    /// Publishes a key package event to configured relays.
    /// The key package event should already be signed and encoded as JSON.
    /// - Parameters:
    ///   - keyPackageEventJson: The signed key package event as JSON
    ///   - relayOverride: Optional specific relays to publish to
    /// - Returns: The published NostrEvent
    @MainActor
    func publishKeyPackage(
        keyPackageEventJson: String,
        relayOverride: [URL]? = nil
    ) async throws -> NostrEvent {
        let event = try NostrEvent.fromJson(json: keyPackageEventJson)
        let relays = try await resolveRelays(override: relayOverride)

        logger.info("📤 Publishing key package to \(relays.count) relay(s)")
        logger.debug("   Event ID: \(event.idHex.prefix(16))...")
        logger.debug("   Author: \(event.pubkey.prefix(16))...")

        try await nostrClient.publish(event: event, to: relays)

        logger.info("✅ Key package published successfully")
        return event
    }

    /// Fetches key packages for a given parent from Nostr relays.
    /// - Parameters:
    ///   - parentKey: The parent's public key (hex or npub/bech32 format)
    ///   - relayOverride: Optional specific relays to query
    ///   - timeout: How long to wait for results (default 5 seconds)
    /// - Returns: Array of key package event JSON strings
    @MainActor
    func fetchKeyPackages(
        for parentKey: String,
        relayOverride: [URL]? = nil,
        timeout: TimeInterval = 5
    ) async throws -> [String] {
        // Normalize the key to hex format
        let hexKey = try normalizeToHex(parentKey)
        let publicKey = try NostrSDK.PublicKey.parse(publicKey: hexKey)

        let relays = try await resolveRelays(override: relayOverride)

        logger.info("🔍 Fetching key packages for \(hexKey.prefix(16))... from \(relays.count) relay(s)")

        // Create subscription filter for key packages from this author
        var filter = Filter()
        filter = filter.kinds(kinds: [Kind(kind: MarmotEventKind.keyPackage.rawValue)])
        filter = filter.authors(authors: [publicKey])

        let subscriptionId = "kp-discovery-\(UUID().uuidString.prefix(8))"

        // Subscribe and collect events
        var collectedEvents: [NostrEvent] = []
        let eventStream = await nostrClient.events()

        try await nostrClient.subscribe(id: subscriptionId, filters: [filter], on: relays)

        // Collect events with timeout
        let deadline = Date().addingTimeInterval(timeout)

        // Use a task to collect events
        let collectTask = Task { @MainActor () -> [NostrEvent] in
            var events: [NostrEvent] = []
            for await event in eventStream {
                // Only collect key package events from our target author
                if event.kind().asU16() == MarmotEventKind.keyPackage.rawValue &&
                   event.pubkey.lowercased() == hexKey.lowercased() {
                    events.append(event)
                    logger.debug("   📦 Received key package: \(event.idHex.prefix(16))...")
                }

                // Check if we should stop
                if Date() > deadline {
                    break
                }
            }
            return events
        }

        // Wait for timeout, then cancel collection
        try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        collectTask.cancel()

        // Unsubscribe
        await nostrClient.unsubscribe(id: subscriptionId, on: relays)

        // Get collected events (may be partial due to cancellation)
        collectedEvents = (try? await collectTask.value) ?? []

        logger.info("✅ Found \(collectedEvents.count) key package(s) for \(hexKey.prefix(16))...")

        // Convert to JSON strings
        let jsonStrings = collectedEvents.compactMap { event -> String? in
            try? event.asJson()
        }

        return jsonStrings
    }

    /// Fetches key packages with a simpler polling approach that's more reliable.
    @MainActor
    func fetchKeyPackagesPolling(
        for parentKey: String,
        relayOverride: [URL]? = nil,
        timeout: TimeInterval = 5,
        pollInterval: TimeInterval = 0.25
    ) async throws -> [String] {
        let hexKey = try normalizeToHex(parentKey)
        let publicKey = try NostrSDK.PublicKey.parse(publicKey: hexKey)

        let relays = try await resolveRelays(override: relayOverride)

        logger.info("🔍 Polling for key packages for \(hexKey.prefix(16))... from \(relays.count) relay(s)")

        var filter = Filter()
        filter = filter.kinds(kinds: [Kind(kind: MarmotEventKind.keyPackage.rawValue)])
        filter = filter.authors(authors: [publicKey])

        let subscriptionId = "kp-poll-\(UUID().uuidString.prefix(8))"

        // Set up event collection
        var collectedEventIds = Set<String>()
        var collectedEvents: [NostrEvent] = []

        // Subscribe to events
        let eventStream = await nostrClient.events()
        try await nostrClient.subscribe(id: subscriptionId, filters: [filter], on: relays)

        // Start collection task
        let collectTask = Task { @MainActor in
            for await event in eventStream {
                if event.kind().asU16() == MarmotEventKind.keyPackage.rawValue &&
                   event.pubkey.lowercased() == hexKey.lowercased() {
                    let eventId = event.idHex
                    if !collectedEventIds.contains(eventId) {
                        collectedEventIds.insert(eventId)
                        collectedEvents.append(event)
                        logger.debug("   📦 Collected key package: \(eventId.prefix(16))...")
                    }
                }
            }
        }

        // Poll until timeout
        let iterations = Int(timeout / pollInterval)
        for i in 0..<iterations {
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            if !collectedEvents.isEmpty {
                logger.debug("   Found \(collectedEvents.count) event(s) after \(i+1) polls")
            }
        }

        // Cleanup
        collectTask.cancel()
        await nostrClient.unsubscribe(id: subscriptionId, on: relays)

        logger.info("✅ Collected \(collectedEvents.count) key package(s)")

        return collectedEvents.compactMap { try? $0.asJson() }
    }

    // MARK: - Private Helpers

    private nonisolated func normalizeToHex(_ key: String) throws -> String {
        // If it's already hex (64 chars), return as-is
        if key.count == 64 && key.allSatisfy({ $0.isHexDigit }) {
            return key.lowercased()
        }

        // Try to parse as bech32 (npub)
        if key.hasPrefix("npub") {
            do {
                let pubkey = try NostrSDK.PublicKey.parse(publicKey: key)
                return pubkey.toHex().lowercased()
            } catch {
                throw DiscoveryError.invalidPublicKey(key)
            }
        }

        // Try parsing directly
        do {
            let pubkey = try NostrSDK.PublicKey.parse(publicKey: key)
            return pubkey.toHex().lowercased()
        } catch {
            throw DiscoveryError.invalidPublicKey(key)
        }
    }

    @MainActor
    private func resolveRelays(override: [URL]?) async throws -> [URL] {
        let configured: [URL]
        if let override, !override.isEmpty {
            configured = override
        } else {
            configured = await relayDirectory.currentRelayURLs()
        }

        guard !configured.isEmpty else {
            throw DiscoveryError.noRelaysConnected
        }

        // Filter to connected relays
        let statuses = await nostrClient.relayStatuses()
        let connectedSet = Set(statuses.filter { $0.status == .connected }.map(\.url))
        let connected = configured.filter { connectedSet.contains($0) }

        guard !connected.isEmpty else {
            throw DiscoveryError.noRelaysConnected
        }

        return connected
    }
}
