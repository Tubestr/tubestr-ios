//
//  KeyPackageDiscoveryTests.swift
//  MyTubeTests
//
//  Created by Assistant on 11/26/25.
//

import XCTest
@testable import MyTube

/// Tests for Nostr-based key package discovery.
/// These tests verify that key packages can be published to and fetched from
/// real Nostr relays, enabling key exchange without invitation links.
final class KeyPackageDiscoveryTests: XCTestCase {

    // MARK: - Publishing Tests

    @MainActor
    func testPublishKeyPackageToRelays() async throws {
        print("\n========== Test: Publish Key Package to Relays ==========")

        // Setup test environment
        let family = try await TestFamilyEnvironment(name: "Publisher")

        // Create identity
        print("🔑 Setting up identity...")
        _ = try await family.setupIdentity()

        // Wait for relay connection
        print("📡 Waiting for relay connection...")
        let connected = try await waitUntil("Relay connected", timeout: 10) {
            let statuses = await family.nostrClient.relayStatuses()
            return statuses.contains { $0.status == .connected }
        }
        XCTAssertTrue(connected, "Failed to connect to relay")
        print("✅ Connected to relay")

        // Get parent identity
        guard let parentIdentity = try family.environment.identityManager.parentIdentity() else {
            return XCTFail("No parent identity")
        }
        print("   Parent npub: \(parentIdentity.publicKeyBech32 ?? "N/A")")

        // Create key package
        print("📦 Creating key package...")
        let relays = await family.environment.relayDirectory.currentRelayURLs()
        let relayStrings = relays.map(\.absoluteString)

        let keyPackageResult = try await family.environment.mdkActor.createKeyPackage(
            forPublicKey: parentIdentity.publicKeyHex,
            relays: relayStrings
        )

        // Encode key package as Nostr event
        let keyPackageEventJson = try KeyPackageEventEncoder.encode(
            result: keyPackageResult,
            signingKey: parentIdentity.keyPair
        )
        print("✅ Key package created and encoded")

        // Create discovery service
        let discovery = KeyPackageDiscovery(
            nostrClient: family.nostrClient,
            relayDirectory: family.environment.relayDirectory
        )

        // Publish to relays
        print("📤 Publishing key package to relays...")
        let publishedEvent = try await discovery.publishKeyPackage(keyPackageEventJson: keyPackageEventJson)

        XCTAssertFalse(publishedEvent.idHex.isEmpty, "Published event should have an ID")
        XCTAssertEqual(publishedEvent.kind().asU16(), 443, "Should be kind 443 (key package)")
        XCTAssertEqual(publishedEvent.pubkey.lowercased(), parentIdentity.publicKeyHex.lowercased())

        print("✅ Key package published successfully")
        print("   Event ID: \(publishedEvent.idHex.prefix(16))...")
        print("   Kind: \(publishedEvent.kind().asU16())")
        print("   Author: \(publishedEvent.pubkey.prefix(16))...")

        print("\n========== Test Passed ==========\n")
    }

    // MARK: - Fetching Tests

    @MainActor
    func testFetchKeyPackagesByNpub() async throws {
        print("\n========== Test: Fetch Key Packages by Npub ==========")

        // Setup two test environments
        print("👨‍👩‍👧 Setting up Family A (publisher)...")
        let familyA = try await TestFamilyEnvironment(name: "FamilyA")
        _ = try await familyA.setupIdentity()

        print("👨‍👩‍👧 Setting up Family B (fetcher)...")
        let familyB = try await TestFamilyEnvironment(name: "FamilyB")
        _ = try await familyB.setupIdentity()

        // Wait for relay connections
        print("📡 Waiting for relay connections...")
        let aConnected = try await waitUntil("Family A relay connected", timeout: 10) {
            let statuses = await familyA.nostrClient.relayStatuses()
            return statuses.contains { $0.status == .connected }
        }
        let bConnected = try await waitUntil("Family B relay connected", timeout: 10) {
            let statuses = await familyB.nostrClient.relayStatuses()
            return statuses.contains { $0.status == .connected }
        }
        XCTAssertTrue(aConnected && bConnected, "Both families should be connected")
        print("✅ Both families connected to relays")

        // Get Family A's parent identity
        guard let parentA = try familyA.environment.identityManager.parentIdentity() else {
            return XCTFail("No parent identity for Family A")
        }
        let parentANpub = parentA.publicKeyBech32 ?? parentA.publicKeyHex
        print("   Family A parent: \(parentANpub.prefix(20))...")

        // Create and publish key package from Family A
        print("📦 Family A: Creating key package...")
        let relays = await familyA.environment.relayDirectory.currentRelayURLs()
        let keyPackageResult = try await familyA.environment.mdkActor.createKeyPackage(
            forPublicKey: parentA.publicKeyHex,
            relays: relays.map(\.absoluteString)
        )
        let keyPackageJson = try KeyPackageEventEncoder.encode(
            result: keyPackageResult,
            signingKey: parentA.keyPair
        )

        let discoveryA = KeyPackageDiscovery(
            nostrClient: familyA.nostrClient,
            relayDirectory: familyA.environment.relayDirectory
        )

        print("📤 Family A: Publishing key package...")
        let publishedEvent = try await discoveryA.publishKeyPackage(keyPackageEventJson: keyPackageJson)
        print("✅ Published event: \(publishedEvent.idHex.prefix(16))...")

        // Allow some time for propagation
        print("   Waiting 2s for relay propagation...")
        try await Task.sleep(nanoseconds: 2_000_000_000)

        // Family B fetches key packages by npub
        print("🔍 Family B: Fetching key packages for Family A's npub...")
        let discoveryB = KeyPackageDiscovery(
            nostrClient: familyB.nostrClient,
            relayDirectory: familyB.environment.relayDirectory
        )

        let fetchedPackages = try await discoveryB.fetchKeyPackagesPolling(
            for: parentANpub,
            timeout: 5
        )

        print("✅ Fetched \(fetchedPackages.count) key package(s)")

        XCTAssertFalse(fetchedPackages.isEmpty, "Should find at least one key package")

        // Verify the fetched package matches what was published
        if let fetchedJson = fetchedPackages.first {
            // Parse to verify structure
            let fetchedEvent = try NostrEvent.fromJson(json: fetchedJson)
            XCTAssertEqual(fetchedEvent.kind().asU16(), 443)
            XCTAssertEqual(fetchedEvent.pubkey.lowercased(), parentA.publicKeyHex.lowercased())
            print("   Fetched event ID: \(fetchedEvent.idHex.prefix(16))...")
            print("   Author matches: ✅")
        }

        print("\n========== Test Passed ==========\n")
    }

    // MARK: - End-to-End Key Exchange Tests

    @MainActor
    func testRelayBasedKeyExchange() async throws {
        print("\n========== Test: Relay-Based Key Exchange (No Invitation Link) ==========")

        // Setup two families
        print("👨‍👩‍👧 Setting up Family A...")
        let familyA = try await TestFamilyEnvironment(name: "FamilyA")
        let profileA = try await familyA.setupIdentity()

        print("👨‍👩‍👧 Setting up Family B...")
        let familyB = try await TestFamilyEnvironment(name: "FamilyB")
        _ = try await familyB.setupIdentity()

        // Wait for relay connections
        print("📡 Verifying relay connections...")
        let connected = try await waitUntil("Relays connected", timeout: 10) {
            let aStatuses = await familyA.nostrClient.relayStatuses()
            let bStatuses = await familyB.nostrClient.relayStatuses()
            return aStatuses.contains { $0.status == .connected } &&
                   bStatuses.contains { $0.status == .connected }
        }
        XCTAssertTrue(connected)
        print("✅ Both families connected")

        // Get identities
        guard let parentA = try familyA.environment.identityManager.parentIdentity() else {
            return XCTFail("No parent A identity")
        }
        guard let parentB = try familyB.environment.identityManager.parentIdentity() else {
            return XCTFail("No parent B identity")
        }

        let vmA = familyA.createViewModel()
        let vmB = familyB.createViewModel()
        vmA.loadIdentities()
        vmB.loadIdentities()

        guard let childA = vmA.childIdentities.first(where: { $0.id == profileA.id }) else {
            return XCTFail("Missing child A")
        }
        let childAPublicKey = childA.publicKey ?? childA.identity?.keyPair.publicKeyHex
        guard let childAPublicKey else {
            return XCTFail("Child A has no public key")
        }

        print("   Family A parent: \(parentA.publicKeyHex.prefix(16))...")
        print("   Family A child: \(childAPublicKey.prefix(16))...")
        print("   Family B parent: \(parentB.publicKeyHex.prefix(16))...")

        // Step 1: Family A publishes key packages to relay
        print("\n📦 Step 1: Family A publishes key packages to relay...")
        let relays = await familyA.environment.relayDirectory.currentRelayURLs()
        let keyPackageResult = try await familyA.environment.mdkActor.createKeyPackage(
            forPublicKey: parentA.publicKeyHex,
            relays: relays.map(\.absoluteString)
        )
        let keyPackageJson = try KeyPackageEventEncoder.encode(
            result: keyPackageResult,
            signingKey: parentA.keyPair
        )

        let discoveryA = KeyPackageDiscovery(
            nostrClient: familyA.nostrClient,
            relayDirectory: familyA.environment.relayDirectory
        )
        let publishedEvent = try await discoveryA.publishKeyPackage(keyPackageEventJson: keyPackageJson)
        print("✅ Key package published: \(publishedEvent.idHex.prefix(16))...")

        // Wait for propagation
        print("   Waiting 2s for relay propagation...")
        try await Task.sleep(nanoseconds: 2_000_000_000)

        // Step 2: Family B discovers Family A's key packages by npub
        print("\n🔍 Step 2: Family B discovers Family A's key packages by npub...")
        let discoveryB = KeyPackageDiscovery(
            nostrClient: familyB.nostrClient,
            relayDirectory: familyB.environment.relayDirectory
        )

        // Family B only knows Family A's npub - no invitation link needed!
        let parentANpub = parentA.publicKeyBech32 ?? parentA.publicKeyHex

        let discoveredPackages = try await discoveryB.fetchKeyPackagesPolling(
            for: parentANpub,
            timeout: 5
        )

        XCTAssertFalse(discoveredPackages.isEmpty, "Should discover key packages")
        print("✅ Discovered \(discoveredPackages.count) key package(s)")

        // Step 3: Family B uses discovered key packages to create group
        print("\n🤝 Step 3: Family B creates group using discovered key packages...")

        // Create v3 invite (no embedded packages) and fetch via view model
        let invite = ParentZoneViewModel.FollowInvite(
            version: 3,
            childName: childA.profile.name,
            childPublicKey: childAPublicKey,
            parentPublicKey: parentANpub
        )

        // Since we already discovered packages, we can fetch via the view model
        // This uses the same KeyPackageDiscovery service
        await vmB.fetchKeyPackagesFromRelay(for: invite)

        // Wait for fetch to complete
        let fetchComplete = try await waitUntil("Key packages fetched via VM", timeout: 10) {
            if case .fetched = vmB.keyPackageFetchState { return true }
            if case .failed = vmB.keyPackageFetchState { return true }
            return false
        }
        XCTAssertTrue(fetchComplete, "Key package fetch should complete")

        if case .failed(_, let error) = vmB.keyPackageFetchState {
            // This is expected to succeed since we already found packages above
            XCTFail("Key package fetch failed: \(error)")
            return
        }
        if case .fetched(_, let count) = vmB.keyPackageFetchState {
            print("   Stored \(count) key package(s) for parent A via VM")
        }

        // Now Family B can submit a follow request using the discovered packages
        // This is similar to what happens with invitation, but key packages came from relay!
        guard let childB = vmB.childIdentities.first else {
            return XCTFail("Missing child B")
        }

        print("📤 Family B: Submitting follow request...")
        let error = await vmB.submitFollowRequest(
            childId: childB.id,
            targetChildKey: childAPublicKey,
            targetParentKey: parentANpub
        )
        if let error {
            print("   ⚠️ Follow request warning: \(error)")
        }
        print("✅ Follow request submitted")

        // Wait for group creation
        print("   Waiting for group creation...")
        try await Task.sleep(nanoseconds: 1_000_000_000)

        // Verify Family B has a group
        let groupCreated = try await waitUntil("Family B group created", timeout: 10) {
            let groups = try await familyB.environment.mdkActor.getGroups()
            return !groups.isEmpty
        }
        XCTAssertTrue(groupCreated, "Family B should have created a group")
        print("✅ Family B created group")

        // Step 4: Family A receives welcome and accepts
        print("\n📬 Step 4: Family A receives welcome...")
        let welcomeReceived = try await waitUntil("Family A receives welcome", timeout: 10) {
            await vmA.refreshPendingWelcomes()
            return !vmA.pendingWelcomes.isEmpty
        }

        if welcomeReceived, let welcome = vmA.pendingWelcomes.first {
            print("✅ Family A received welcome: \(welcome.groupName)")
            print("🤝 Family A: Accepting welcome...")
            await vmA.acceptWelcome(welcome, linkToChildId: profileA.id)
            print("✅ Welcome accepted")
        } else {
            print("⚠️ No welcome received (may need more propagation time)")
        }

        // Final verification
        try await Task.sleep(nanoseconds: 1_000_000_000)

        let groupsA = try await familyA.environment.mdkActor.getGroups()
        let groupsB = try await familyB.environment.mdkActor.getGroups()

        print("\n📊 Final state:")
        print("   Family A groups: \(groupsA.count)")
        print("   Family B groups: \(groupsB.count)")

        // At minimum, Family B should have created a group
        XCTAssertFalse(groupsB.isEmpty, "Family B should have at least one group")

        print("\n========== Test Completed ==========\n")
    }

    // MARK: - Helpers

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 10,
        pollInterval: TimeInterval = 0.25,
        condition: @escaping () async throws -> Bool
    ) async throws -> Bool {
        let iterations = max(1, Int(timeout / pollInterval))
        for _ in 0..<iterations {
            if try await condition() {
                return true
            }
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
        XCTFail("Timed out waiting for \(description)")
        return false
    }
}
