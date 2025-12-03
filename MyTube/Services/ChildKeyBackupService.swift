//
//  ChildKeyBackupService.swift
//  MyTube
//
//  Created by Codex on 11/26/25.
//

import Foundation
import NostrSDK
import OSLog

/// Backup data structure for a single child's keys
struct ChildKeyBackup: Codable, Sendable {
    let childId: String        // UUID string
    let childName: String
    let nsec: String           // bech32 nsec
    let createdAt: Double      // Unix timestamp
}

enum ChildKeyBackupError: Error {
    case parentIdentityMissing
    case relaysUnavailable
    case encryptionFailed
    case decryptionFailed
    case encodingFailed
    case noBackupFound
}

/// Service for backing up and recovering child Nostr keys using NIP-44 encrypted events.
///
/// Child nsecs are backed up as kind 30078 events (NIP-78 application-specific data),
/// encrypted to the parent's own pubkey. This enables multi-device recovery when
/// the parent imports their nsec on a new device.
actor ChildKeyBackupService {
    private static let backupKind = EventKind(kind: 30078)
    private static let dTag = "mytube:child_keys"
    private static let publishTimeoutNanoseconds: UInt64 = 10 * NSEC_PER_SEC

    private let identityManager: IdentityManager
    private let keyStore: KeychainKeyStore
    private let profileStore: ProfileStore
    private let nostrClient: NostrClient
    private let relayDirectory: RelayDirectory
    private let signer: NostrEventSigner
    private let logger = Logger(subsystem: "com.mytube", category: "ChildKeyBackupService")

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        identityManager: IdentityManager,
        keyStore: KeychainKeyStore,
        profileStore: ProfileStore,
        nostrClient: NostrClient,
        relayDirectory: RelayDirectory,
        signer: NostrEventSigner = NostrEventSigner()
    ) {
        self.identityManager = identityManager
        self.keyStore = keyStore
        self.profileStore = profileStore
        self.nostrClient = nostrClient
        self.relayDirectory = relayDirectory
        self.signer = signer

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        self.decoder = JSONDecoder()
    }

    /// Publishes an encrypted backup of all child keys to Nostr relays.
    ///
    /// The backup is encrypted using NIP-44 to the parent's own pubkey,
    /// ensuring only the parent can decrypt it on any device with their nsec.
    @MainActor
    func publishBackup() async throws {
        guard let parentIdentity = try identityManager.parentIdentity() else {
            throw ChildKeyBackupError.parentIdentityMissing
        }

        let relays = await relayDirectory.currentRelayURLs()
        guard !relays.isEmpty else {
            throw ChildKeyBackupError.relaysUnavailable
        }

        // Gather all child identities
        let childIdentities = try identityManager.allChildIdentities()
        let backups = childIdentities.map { child in
            ChildKeyBackup(
                childId: child.profile.id.uuidString,
                childName: child.profile.name,
                nsec: child.keyPair.secretKeyBech32 ?? child.keyPair.exportSecretKeyHex(),
                createdAt: child.keyPair.createdAt.timeIntervalSince1970
            )
        }

        // Serialize to JSON
        guard let jsonData = try? encoder.encode(backups),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw ChildKeyBackupError.encodingFailed
        }

        // Encrypt to self using NIP-44
        let parentKeys = try parentIdentity.keyPair.makeKeys()
        let encryptedContent = try nip44Encrypt(
            secretKey: parentKeys.secretKey(),
            publicKey: parentKeys.publicKey(),
            content: jsonString,
            version: .v2
        )

        // Build event with d tag for replaceable event
        let dTag = try Tag.parse(data: ["d", Self.dTag])
        let event = try signer.makeEvent(
            kind: Self.backupKind,
            tags: [dTag],
            content: encryptedContent,
            keyPair: parentIdentity.keyPair
        )

        // Publish with timeout
        try await publish(event: event, to: relays)
        logger.info("Published child key backup with \(backups.count) children")
    }

    /// Fetches and decrypts child key backups from Nostr relays.
    ///
    /// This is used during recovery when a parent imports their nsec on a new device.
    /// Returns the list of child key backups that can be restored to Keychain.
    @MainActor
    func fetchBackup() async throws -> [ChildKeyBackup] {
        guard let parentIdentity = try identityManager.parentIdentity() else {
            throw ChildKeyBackupError.parentIdentityMissing
        }

        let relays = await relayDirectory.currentRelayURLs()
        guard !relays.isEmpty else {
            throw ChildKeyBackupError.relaysUnavailable
        }

        // Subscribe to kind 30078 events from ourselves
        // We'll filter by d tag when processing the events
        let subscriptionId = "child_key_backup_\(UUID().uuidString.prefix(8))"
        var filter = Filter()
        filter = filter.authors(authors: [try parentIdentity.keyPair.publicKey()])
        filter = filter.kinds(kinds: [Kind(kind: Self.backupKind.asU16())])
        filter = filter.limit(limit: 10)

        // Collect events with timeout
        var backupEvent: NostrEvent?
        let eventStream = await nostrClient.events()

        try await nostrClient.subscribe(id: subscriptionId, filters: [filter], on: relays)
        defer {
            Task { @MainActor in
                await nostrClient.unsubscribe(id: subscriptionId, on: relays)
            }
        }

        // Wait for events with timeout using a proper racing pattern
        backupEvent = await withTaskGroup(of: NostrEvent?.self) { group in
            // Event listener task
            group.addTask { @MainActor in
                for await event in eventStream {
                    let eventKind = event.kind()
                    if eventKind.asU16() == Self.backupKind.asU16() {
                        // Check for our d tag
                        let tags = event.tags().toVec()
                        let hasDTag = tags.contains { tag in
                            let parts = tag.asVec()
                            return parts.count >= 2 && parts[0] == "d" && parts[1] == Self.dTag
                        }
                        if hasDTag {
                            return event
                        }
                    }
                }
                return nil
            }

            // Timeout task
            group.addTask {
                try? await Task.sleep(nanoseconds: Self.publishTimeoutNanoseconds)
                return nil
            }

            // Return first non-nil result, or nil on timeout
            for await result in group {
                if let event = result {
                    group.cancelAll()
                    return event
                }
                // If we got nil (timeout), cancel remaining tasks and return nil
                group.cancelAll()
                return nil
            }
            return nil
        }

        guard let event = backupEvent else {
            logger.info("No child key backup found on relays")
            throw ChildKeyBackupError.noBackupFound
        }

        // Decrypt content using NIP-44
        let parentKeys = try parentIdentity.keyPair.makeKeys()
        let decryptedContent: String
        do {
            decryptedContent = try nip44Decrypt(
                secretKey: parentKeys.secretKey(),
                publicKey: parentKeys.publicKey(),
                payload: event.content()
            )
        } catch {
            logger.error("Failed to decrypt child key backup: \(error.localizedDescription)")
            throw ChildKeyBackupError.decryptionFailed
        }

        // Parse JSON
        guard let jsonData = decryptedContent.data(using: .utf8),
              let backups = try? decoder.decode([ChildKeyBackup].self, from: jsonData) else {
            throw ChildKeyBackupError.decryptionFailed
        }

        logger.info("Fetched child key backup with \(backups.count) children")
        return backups
    }

    /// Restores child keys from a backup to the Keychain and creates corresponding profiles.
    ///
    /// For each backup entry:
    /// 1. Creates a ProfileModel if it doesn't exist
    /// 2. Stores the keypair in Keychain
    /// Returns the number of children successfully restored.
    @MainActor
    @discardableResult
    func restoreFromBackup(_ backups: [ChildKeyBackup]) async throws -> Int {
        var restoredCount = 0

        for backup in backups {
            guard let childId = UUID(uuidString: backup.childId) else {
                logger.warning("Skipping invalid child ID: \(backup.childId)")
                continue
            }

            // Check if we already have this keypair
            if (try? keyStore.fetchKeyPair(role: .child(id: childId))) != nil {
                logger.info("Child \(backup.childName) already has keypair, skipping")
                continue
            }

            // Parse the nsec
            let keyPair: NostrKeyPair
            do {
                if backup.nsec.lowercased().hasPrefix("nsec") {
                    // bech32 format
                    let decoded = try NIP19.decode(backup.nsec)
                    guard decoded.kind == .nsec else {
                        logger.warning("Invalid nsec format for child \(backup.childName)")
                        continue
                    }
                    keyPair = try NostrKeyPair(
                        privateKeyData: decoded.data,
                        createdAt: Date(timeIntervalSince1970: backup.createdAt)
                    )
                } else {
                    // hex format
                    keyPair = try NostrKeyPair(
                        secretKeyHex: backup.nsec,
                        createdAt: Date(timeIntervalSince1970: backup.createdAt)
                    )
                }
            } catch {
                logger.warning("Failed to parse nsec for child \(backup.childName): \(error.localizedDescription)")
                continue
            }

            // Create profile if it doesn't exist (use default theme, can be changed later)
            let existingProfiles = (try? profileStore.fetchProfiles()) ?? []
            let profileExists = existingProfiles.contains { $0.id == childId }

            if !profileExists {
                do {
                    // Create profile with the exact UUID from backup
                    _ = try profileStore.createProfileWithId(
                        id: childId,
                        name: backup.childName,
                        theme: .campfire,
                        avatarAsset: ThemeDescriptor.campfire.defaultAvatarAsset
                    )
                    logger.info("Created profile for restored child \(backup.childName)")
                } catch {
                    logger.warning("Failed to create profile for child \(backup.childName): \(error.localizedDescription)")
                    continue
                }
            }

            // Store keypair in Keychain
            try keyStore.storeKeyPair(keyPair, role: .child(id: childId), requireBiometrics: false)
            logger.info("Restored keypair for child \(backup.childName)")
            restoredCount += 1
        }

        return restoredCount
    }

    /// Performs the full recovery flow: fetch backup from relays, restore keys, create profiles.
    ///
    /// Call this after importing a parent nsec on a new device.
    /// Returns the number of children successfully recovered, or nil if no backup was found.
    @MainActor
    func recoverChildKeys() async -> Int? {
        do {
            let backups = try await fetchBackup()
            if backups.isEmpty {
                logger.info("No children to recover from backup")
                return 0
            }

            let count = try await restoreFromBackup(backups)
            logger.info("Recovered \(count) child(ren) from backup")
            return count
        } catch ChildKeyBackupError.noBackupFound {
            logger.info("No child key backup found on relays")
            return nil
        } catch {
            logger.error("Child key recovery failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Private

    @MainActor
    private func publish(event: NostrEvent, to relays: [URL]) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                try await self.nostrClient.publish(event: event, to: relays)
            }

            group.addTask {
                try await Task.sleep(nanoseconds: Self.publishTimeoutNanoseconds)
                throw ChildKeyBackupError.relaysUnavailable
            }

            defer { group.cancelAll() }
            _ = try await group.next()
        }
    }
}
