//
//  IdentityManagerTests.swift
//  MyTubeTests
//
//  Created by Codex on 11/06/25.
//

import XCTest
@testable import MyTube

final class IdentityManagerTests: XCTestCase {
    func testParentAndChildIdentityLifecycle() throws {
        let persistence = PersistenceController(inMemory: true)
        let profileStore = ProfileStore(persistence: persistence)

        let profile = try profileStore.createProfile(
            name: "Test Child",
            theme: .ocean,
            avatarAsset: "avatar.dolphin"
        )

        let keyStore = KeychainKeyStore(service: "IdentityManagerTests.\(UUID().uuidString)")
        defer {
            try? keyStore.removeKeyPair(role: .parent)
        }
        try? keyStore.removeKeyPair(role: .parent)

        let identityManager = IdentityManager(keyStore: keyStore, profileStore: profileStore)

        XCTAssertFalse(identityManager.hasParentIdentity())

        let parent = try identityManager.generateParentIdentity(requireBiometrics: false)
        XCTAssertNotNil(parent.publicKeyBech32)
        XCTAssertTrue(identityManager.hasParentIdentity())

        let fetchedParent = try identityManager.parentIdentity()
        XCTAssertEqual(fetchedParent?.publicKeyHex, parent.publicKeyHex)

        // Child won't have identity until we create one for it
        let existingChild = identityManager.childIdentity(for: profile)
        XCTAssertNil(existingChild, "Profile without keypair should return nil")

        // Use ensureChildIdentity to generate keypair
        let child = try identityManager.ensureChildIdentity(for: profile)
        XCTAssertEqual(child.profile.id, profile.id)
        XCTAssertNotNil(child.publicKeyHex)
        // Children now have their own Nostr keypairs
        XCTAssertNotNil(child.secretKeyBech32)
    }

    func testCreateAndImportChildProfile() throws {
        let persistence = PersistenceController(inMemory: true)
        let profileStore = ProfileStore(persistence: persistence)
        let keyStore = KeychainKeyStore(service: "IdentityManagerTests.\(UUID().uuidString)")
        defer { try? keyStore.removeAll() }

        let identityManager = IdentityManager(keyStore: keyStore, profileStore: profileStore)
        _ = try identityManager.generateParentIdentity(requireBiometrics: false)

        let created = try identityManager.createChildIdentity(
            name: "Nova",
            theme: .galaxy,
            avatarAsset: "avatar.dolphin"
        )
        XCTAssertEqual(created.profile.name, "Nova")
        // Children now have their own Nostr keypairs
        XCTAssertNotNil(created.secretKeyBech32)
        XCTAssertNotNil(created.publicKeyHex)

        // Test creating another child profile
        let second = try identityManager.createChildIdentity(
            name: "Nova Backup",
            theme: .ocean,
            avatarAsset: "avatar.dolphin"
        )
        XCTAssertEqual(second.profile.name, "Nova Backup")
        // Each child has unique Nostr keypair
        XCTAssertNotEqual(second.publicKeyHex, created.publicKeyHex)
        XCTAssertNotNil(second.secretKeyBech32)
    }
}
