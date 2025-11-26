//
//  SimpleMarmotTest.swift
//  MyTubeTests
//
//  Created by Assistant on 11/18/25.
//

import XCTest
@testable import MyTube

final class SimpleMarmotTest: XCTestCase {
    @MainActor
    func testBasicSetup() async throws {
        print("\n🧪 Testing basic Marmot setup...")
        
        let familyA = try await TestFamilyEnvironment(name: "FamilyA")
        print("✅ Created Family A environment")
        
        let profileA = try await familyA.setupIdentity()
        print("✅ Created Family A identity: \(profileA.name)")
        
        let vmA = familyA.createViewModel()
        vmA.loadIdentities()
        print("✅ Loaded identities, found \(vmA.childIdentities.count) child(ren)")
        
        guard let childA = vmA.childIdentities.first(where: { $0.id == profileA.id }) else {
            return XCTFail("Child identity not found")
        }
        
        guard let parentIdentity = try familyA.environment.identityManager.parentIdentity() else {
            return XCTFail("Parent identity not found")
        }
        
        print("✅ Parent key: \(parentIdentity.publicKeyHex.prefix(16))...")
        print("✅ Child key: \(childA.publicKey?.prefix(16) ?? "none")...")
        
        // Try creating a key package
        let relays = await familyA.environment.relayDirectory.currentRelayURLs()
        print("✅ Found \(relays.count) relay(s)")
        
        let keyPackageResult = try await familyA.environment.mdkActor.createKeyPackage(
            forPublicKey: parentIdentity.publicKeyHex,
            relays: relays.map(\.absoluteString)
        )
        print("✅ Created key package")
        
        // Check MDK stats
        let stats = await familyA.environment.mdkActor.stats()
        print("✅ MDK stats: \(stats.groupCount) group(s), \(stats.pendingWelcomeCount) pending welcome(s)")
        
        print("🎉 Basic setup test passed!\n")
    }
    
    @MainActor
    func testFollowRequestSubmission() async throws {
        print("\n🧪 Testing follow request submission...")
        
        let familyA = try await TestFamilyEnvironment(name: "FamilyA")
        let familyB = try await TestFamilyEnvironment(name: "FamilyB")
        print("✅ Created both families")
        
        let profileA = try await familyA.setupIdentity()
        _ = try await familyB.setupIdentity()
        print("✅ Setup identities")
        
        let vmA = familyA.createViewModel()
        let vmB = familyB.createViewModel()
        vmA.loadIdentities()
        vmB.loadIdentities()
        print("✅ Loaded view models")
        
        guard let childA = vmA.childIdentities.first(where: { $0.id == profileA.id }),
              let childB = vmB.childIdentities.first,
              let parentIdentity = try familyA.environment.identityManager.parentIdentity(),
              let childPublicKey = childA.publicKey else {
            return XCTFail("Missing required identities")
        }
        print("✅ Got all identities")
        
        // Publish key package to relay
        print("📤 Publishing key package to relay...")
        await vmA.publishKeyPackageToRelays()
        print("✅ Key package published")

        // Wait for relay propagation
        try await Task.sleep(nanoseconds: 2_000_000_000)

        // Create invite (v3 - no embedded key packages)
        let invite = ParentZoneViewModel.FollowInvite(
            version: 3,
            childName: childA.profile.name,
            childPublicKey: childPublicKey,
            parentPublicKey: parentIdentity.publicKeyBech32 ?? parentIdentity.publicKeyHex
        )

        // Fetch key packages from relay
        print("🔍 Fetching key packages from relay...")
        await vmB.fetchKeyPackagesFromRelay(for: invite)

        // Wait for fetch to complete
        let fetchSuccess = try await waitUntil("Key packages fetched", timeout: 10) {
            if case .fetched = vmB.keyPackageFetchState { return true }
            if case .failed = vmB.keyPackageFetchState { return true }
            return false
        }
        XCTAssertTrue(fetchSuccess, "Key package fetch should complete")

        if case .failed(_, let error) = vmB.keyPackageFetchState {
            XCTFail("Key package fetch failed: \(error)")
            return
        }
        print("✅ Key packages fetched")
        
        // Submit follow request
        print("📤 Submitting follow request...")
        let error = await vmB.submitFollowRequest(
            childId: childB.id,
            targetChildKey: invite.childPublicKey,
            targetParentKey: invite.parentPublicKey
        )
        
        XCTAssertNil(error, "Follow request should not fail, but got: \(error ?? "unknown")")
        print("✅ Follow request submitted without error")
        
        // Give it a moment to process
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Check if group was created
        do {
            let groups = try await familyB.environment.mdkActor.getGroups()
            print("✅ Family B has \(groups.count) group(s)")
            
            if let group = groups.first {
                print("   Group name: \(group.name)")
                print("   Group state: \(group.state)")
                let members = try await familyB.environment.mdkActor.getMembers(inGroup: group.mlsGroupId)
                print("   Members: \(members.count)")
            }
            
            XCTAssertGreaterThan(groups.count, 0, "Should have at least one group")
            if let group = groups.first {
                let members = try await familyB.environment.mdkActor.getMembers(inGroup: group.mlsGroupId)
                XCTAssertGreaterThanOrEqual(members.count, 2, "Should have at least 2 members")
            }
        } catch {
            print("❌ Error fetching groups: \(error)")
            throw error
        }
        
        print("🎉 Follow request submission test passed!\n")
    }
    
    @MainActor
    func testKeyPackageStorage() async throws {
        print("\n🧪 Testing key package storage...")
        
        let familyA = try await TestFamilyEnvironment(name: "FamilyA")
        let familyB = try await TestFamilyEnvironment(name: "FamilyB")
        
        _ = try await familyA.setupIdentity()
        _ = try await familyB.setupIdentity()
        
        let vmA = familyA.createViewModel()
        let vmB = familyB.createViewModel()
        vmA.loadIdentities()
        vmB.loadIdentities()
        
        guard let parentIdentity = try familyA.environment.identityManager.parentIdentity() else {
            return XCTFail("Missing parent identity")
        }
        print("✅ Parent A key: \(parentIdentity.publicKeyHex.prefix(16))...")

        // Wait for relay connection
        let connected = try await waitUntil("Relay connected", timeout: 10) {
            let statuses = await familyA.nostrClient.relayStatuses()
            return statuses.contains { $0.status == .connected }
        }
        XCTAssertTrue(connected, "Relay should be connected")

        // Publish key package to relay
        print("📤 Publishing key package to relay...")
        await vmA.publishKeyPackageToRelays()
        print("✅ Published key package")

        // Wait for relay propagation
        try await Task.sleep(nanoseconds: 2_000_000_000)

        // Create invite (v3 - no embedded key packages)
        let invite = ParentZoneViewModel.FollowInvite(
            version: 3,
            childName: "TestChild",
            childPublicKey: "test_child_key",
            parentPublicKey: parentIdentity.publicKeyBech32 ?? parentIdentity.publicKeyHex
        )
        print("✅ Created invite")

        // Fetch key packages from relay
        print("🔍 Fetching key packages from relay...")
        await vmB.fetchKeyPackagesFromRelay(for: invite)

        // Wait for fetch to complete
        let fetchComplete = try await waitUntil("Key packages fetched", timeout: 10) {
            if case .fetched = vmB.keyPackageFetchState { return true }
            if case .failed = vmB.keyPackageFetchState { return true }
            return false
        }
        XCTAssertTrue(fetchComplete, "Key package fetch should complete")

        // Verify storage
        let hasPackages = vmB.hasPendingKeyPackages(for: invite.parentPublicKey)
        print("   Has pending packages for parent: \(hasPackages)")

        if case .fetched(_, let count) = vmB.keyPackageFetchState {
            print("   Fetched \(count) key package(s)")
            XCTAssertGreaterThan(count, 0, "Should have fetched at least one key package")
        } else if case .failed(_, let error) = vmB.keyPackageFetchState {
            XCTFail("Key package fetch failed: \(error)")
        }

        XCTAssertTrue(hasPackages, "Should have pending key packages after fetching from relay")
        print("🎉 Key package storage test passed!\n")
    }

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

