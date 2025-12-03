# Multi-Device Support Implementation Plan

## Overview

This document outlines the implementation plan for multi-device support in MyTube, enabling parents to use the app across multiple iPads while maintaining cryptographic security guarantees.

### Design Decisions

- **Vault encryption**: nsec-derived key (HKDF-SHA256) - no passphrase needed
- **Recovery**: Parent nsec alone is sufficient to restore everything. If nsec is lost, recovery is not possible (accepted trade-off for cryptographic security)
- **Device model**: Primary device for admin operations; secondary devices are read/share only. Any device can be promoted to primary.
- **User flow**: Automatic vault creation for all new users
- **MLS integration**: Each device gets a derived Nostr subkey; the device itself must generate and retain its MLS key package (MDK generates MLS keys internally; no injected seeds)
- **Child identity**: Children have their own npub/nsec keypairs, but parent signs all messages on their behalf (child attribution via `child_profile_id` + `child_pubkey` in payloads)
- **Device linking (v1)**: Simple local QR - no Nostr approval flow. Physical proximity = trust.

### Critical UX Note: nsec Loss Prevention (Included in v1)

The "nsec = everything" model is cryptographically clean but dangerous for non-technical parents. On first-run, we MUST help them secure it:

1. **iCloud Keychain backup (v1, recommended default)** - Store nsec in iCloud Keychain with `kSecAttrSynchronizable = true`
2. **Recovery sheet (v2)** - Generate printable PDF with QR code containing nsec
3. **Clear messaging**: "This secret is like the key to your family's MyTube house. We can't help if it's lost, so we'll help you keep it safe now."

iCloud Keychain is included in v1 because without it, mainstream parents WILL lose nsecs and blame the app.

### Threat Model Summary

**Protected against:**
- Attacker without nsec: can't decrypt vault or Nostr events
- Attacker with partial Nostr visibility: only sees encrypted blobs
- Lost/stolen secondary device: revoke in vault + MLS removal

**NOT protected against:**
- nsec compromise (rooted device, serious breach): full household identity compromised
- Future work: "Migrate to new parent keypair" flow for key rotation

Document this in a separate ThreatModel.md for internal reference.

### User Flows

**Flow 1: New User (First Device = Primary)**
```
1. User opens app for first time
2. Generate parent nsec + wrap key
3. Create device record (deviceId, isPrimary=true)
4. Generate device subkey: HKDF(nsec, deviceId)
5. Create MLS key package locally for device subkey (device keeps MLS keys)
6. Create identity vault (encrypted with HKDF(nsec))
7. Upload vault to MinIO
8. Store nsec + subkey in Keychain
9. Prompt: "Let's secure your account" → iCloud Keychain / Recovery sheet
10. Continue to profile creation
```

**Flow 2: Add Device via QR (Simplified v1)**
```
Primary Device:                         New Device:
1. Tap "Add Device"
2. Generate QR containing:
   - vaultURL
   - nsec
   - parentPubkey
   - expiresAt (5 min)
3. Display QR + warning text            4. Scan QR
                                        5. Validate expiry
                                        6. Derive vault key from nsec
                                        7. Download + decrypt vault
                                        8. Generate new deviceId
                                        9. Generate device subkey (Nostr)
                                        10. Store nsec + subkey in Keychain
                                        11. Locally generate MLS key package (required; MDK stores MLS keys on-device)
                                        12. Publish key package to relays
13. Detect new key package
14. Add new device to ALL groups via addMembers
15. Publish welcomes                    16. Receive + accept welcomes
                                        17. MDK now has group state
18. Update vault with new device
19. Upload updated vault
```

**Flow 3: Recovery with nsec Only (No Other Device)**
```
1. User opens app on new device
2. Chooses "I have an existing account"
3. Enters parent nsec (manual entry or iCloud Keychain restore)
4. Derive vault key: HKDF(nsec, "mytube:vault:v1")
5. Look up vault URL (stored in Nostr replaceable event, encrypted to self)
6. Download and decrypt vault
7. Restore: wrap key, child profiles, device list
8. Generate new device subkey
9. Generate MLS key package locally; publish to relays
10. WAIT: need another device to add to groups, OR
    if this is the only device, groups are empty anyway
```

**Note on Flow 3**: If user lost all devices but has nsec, they can restore identity but NOT existing group memberships (MLS requires another member to add them). This is acceptable - they can re-establish circles with other families.

If nsec is lost and no other device exists, recovery is impossible. This is an accepted trade-off.

### Vault URL Discovery

For recovery (Flow 3), we need to find the vault URL given only nsec. Options:

1. **Nostr replaceable event (recommended)**: Publish kind 30078 (NIP-78) with `d` tag = "mytube:vault", content = encrypted vault URL. Encrypted to self using NIP-44.
2. **Deterministic MinIO path**: `{bucket}/vaults/{sha256(parentPubkey)}.vault` - no lookup needed
3. **iCloud Keychain**: Store vault URL alongside nsec (if using iCloud backup)

For v1, use option 2 (deterministic path) - simplest, no extra Nostr events needed.

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        HOUSEHOLD IDENTITY                        │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐       │
│  │   Parent     │    │    Child     │    │    Child     │       │
│  │   nsec/npub  │    │   nsec/npub  │    │   nsec/npub  │       │
│  │  (signs all) │    │  (no signing)│    │  (no signing)│       │
│  └──────────────┘    └──────────────┘    └──────────────┘       │
└─────────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        ▼                     ▼                     ▼
┌───────────────┐     ┌───────────────┐     ┌───────────────┐
│   Device 1    │     │   Device 2    │     │   Device 3    │
│   (PRIMARY)   │     │  (secondary)  │     │  (secondary)  │
│               │     │               │     │               │
│ • MLS admin   │     │ • Read groups │     │ • Read groups │
│ • Group ops   │     │ • Share video │     │ • Share video │
│ • Device mgmt │     │ • View shared │     │ • View shared │
│               │     │               │     │               │
│ MDK subkey A  │     │ MDK subkey B  │     │ MDK subkey C  │
└───────────────┘     └───────────────┘     └───────────────┘
        │                     │                     │
        └─────────────────────┼─────────────────────┘
                              ▼
                    ┌─────────────────┐
                    │  IDENTITY VAULT │
                    │    (MinIO)      │
                    │                 │
                    │ • Parent nsec   │
                    │ • Child profiles│
                    │ • Group list    │
                    │ • Device list   │
                    │ • Primary flag  │
                    └─────────────────┘
```

---

## Phase 1: Identity Vault Foundation

**Goal**: Create the identity vault system that stores and syncs household state to MinIO.

### 1.1 IdentityVaultService

**New file**: `Services/Identity/IdentityVaultService.swift` (~500 LOC)

```swift
actor IdentityVaultService {
    // NOTE: Vault does NOT contain parent nsec - that's redundant.
    // If you can decrypt the vault, you already have the nsec (since vault key = HKDF(nsec)).
    // Vault stores everything ELSE needed to restore a device.

    struct IdentityVault: Codable {
        let version: Int = 1
        let parentPubkey: String                    // For identification only
        let parentWrapKeyEncrypted: Data            // X25519 wrap key for media encryption
        let childProfiles: [ChildProfileBackup]     // Child nsecs + profiles
        let devices: [DeviceRecord]                 // All linked devices
        let groupMemberships: [GroupMembershipRecord]
        let createdAt: Date
        let updatedAt: Date
    }

    struct DeviceRecord: Codable {
        let deviceId: String
        let deviceName: String
        let isPrimary: Bool
        let subkeyPublicKey: String
        let addedAt: Date
        let lastSeenAt: Date
        let status: DeviceStatus  // active, revoked
    }

    struct ChildProfileBackup: Codable {
        let profileId: String
        let name: String
        let theme: String
        let avatarData: Data?
        let mlsGroupIds: [String]
        let nsecEncrypted: Data      // Child's nsec (encrypted with vault key)
        let npub: String             // Child's public key
    }

    struct GroupMembershipRecord: Codable {
        let mlsGroupId: String
        let groupName: String
        let memberPubkeys: [String]
        let childProfileId: String?
        let createdAt: Date
    }

    // Key derivation: vault key = HKDF(nsec, salt="mytube:vault:v1", info=parentPubkey)
    func deriveVaultKey(from nsec: Data, parentPubkey: String) -> Data

    // Vault CRUD
    func createVault(wrapKey: Data, parentPubkey: String, device: DeviceRecord) async throws -> IdentityVault
    func uploadVault(_ vault: IdentityVault, vaultKey: Data) async throws -> URL
    func downloadVault(from url: URL, vaultKey: Data) async throws -> IdentityVault

    // Update with optimistic concurrency
    func updateVault(
        at url: URL,
        vaultKey: Data,
        changes: (inout IdentityVault) -> Void
    ) async throws {
        var vault = try await downloadVault(from: url, vaultKey: vaultKey)
        let previousUpdatedAt = vault.updatedAt

        changes(&vault)
        vault.updatedAt = Date()

        // Basic concurrency check: warn if remote was modified since we read it
        let remoteVault = try await downloadVault(from: url, vaultKey: vaultKey)
        if remoteVault.updatedAt > previousUpdatedAt {
            // Another device updated the vault - log warning, but proceed
            // Future: implement proper merge or retry
            print("Warning: vault was modified by another device")
        }

        try await uploadVault(vault, vaultKey: vaultKey)
    }

    // Device management
    func addDevice(_ device: DeviceRecord, to vault: inout IdentityVault)
    func revokeDevice(_ deviceId: String, in vault: inout IdentityVault)
    func promoteDevice(_ deviceId: String, in vault: inout IdentityVault)  // Make this device primary
}
```

### 1.2 Vault Key Derivation

Use HKDF-SHA256 to derive vault encryption key from nsec:

```swift
// In CryptoEnvelopeService.swift
func deriveVaultKey(from nsec: Data, parentPubkey: String) -> Data {
    // HKDF-SHA256(nsec, salt="mytube:vault:v1", info=parentPubkey)
    let salt = "mytube:vault:v1".data(using: .utf8)!
    let info = parentPubkey.data(using: .utf8)!
    return hkdfSHA256(secret: nsec, salt: salt, info: info, outputLength: 32)
}
```

### 1.3 KeychainKeyStore Modifications

**File**: `Services/KeychainKeyStore.swift`

Add new storage keys and methods:

```swift
// New storage keys
private static let deviceIdKey = "device.id"
private static let deviceSubkeyPrefix = "device.subkey."
private static let deviceIsPrimaryKey = "device.isPrimary"
private static let vaultURLKey = "vault.url"

// New methods
func storeDeviceId(_ id: String) throws
func fetchDeviceId() -> String?
func storeDeviceSubkey(_ subkey: NostrKeyPair, deviceId: String) throws
func fetchDeviceSubkey(deviceId: String) -> NostrKeyPair?
func storeIsPrimary(_ isPrimary: Bool) throws
func fetchIsPrimary() -> Bool
func storeVaultURL(_ url: URL) throws
func fetchVaultURL() -> URL?
```

### 1.4 IdentityManager Modifications

**File**: `Services/IdentityManager.swift`

Modify `generateParentIdentity()` to also:
1. Generate deviceId (UUID)
2. Generate device subkey
3. Create vault
4. Upload vault
5. Store vault URL

```swift
func generateParentIdentity() async throws {
    // Existing: Generate parent nsec + wrap key
    let parentKey = try NostrKeyPair.generate()
    let wrapKey = try generateWrapKey()

    // New: Generate device identity
    let deviceId = UUID().uuidString
    let deviceSubkey = deviceSubkeyManager.generateSubkey(
        parentNsec: parentKey.secretKey,
        deviceId: deviceId
    )

    // New: Create and upload vault
    var vault = try await vaultService.createVault(
        parentNsec: parentKey.secretKey,
        wrapKey: wrapKey,
        deviceId: deviceId
    )
    let vaultURL = try await vaultService.uploadVault(vault)

    // Store everything
    try keyStore.storeKeyPair(parentKey, role: .parentSigning)
    try keyStore.storeParentWrapKeyPair(wrapKey)
    try keyStore.storeDeviceId(deviceId)
    try keyStore.storeDeviceSubkey(deviceSubkey, deviceId: deviceId)
    try keyStore.storeIsPrimary(true)
    try keyStore.storeVaultURL(vaultURL)
}
```

### 1.5 Deliverables

- [ ] `Services/Identity/IdentityVaultService.swift`
- [ ] `Services/Identity/IdentityVaultModels.swift`
- [ ] Modify `Services/CryptoEnvelopeService.swift` (add HKDF)
- [ ] Modify `Services/KeychainKeyStore.swift`
- [ ] Modify `Services/IdentityManager.swift`
- [ ] Modify `AppEnvironment.swift` (wire vault service)
- [ ] Unit tests for vault encryption/decryption

---

## Phase 2: Device Subkey Architecture

**Goal**: Implement per-device Nostr subkeys (derived from parent nsec) to identify each device in MLS; each device generates its own MLS keys locally.

**MDK constraints to honor**
- Key packages must be generated on the device that will join; MDK generates and stores MLS keys internally and cannot accept injected keys/seeds.
- There is no self-welcome for the creator; additional creator devices must be added via `addMembers` after their key packages are available.
- Messages should use the device pubkey for consistency, but MDK will sign with the stored member keys regardless of the sender string.

### 2.1 DeviceSubkeyManager

**New file**: `Services/Identity/DeviceSubkeyManager.swift` (~300 LOC)

```swift
actor DeviceSubkeyManager {
    private let keyStore: KeychainKeyStore
    private let mdkActor: MdkActor

    // Deterministic subkey derivation
    func generateSubkey(parentNsec: Data, deviceId: String) -> NostrKeyPair {
        // HKDF(nsec, salt=deviceId, info="mytube:subkey:v1") — Nostr identity only
        let derivedSecret = hkdfSHA256(
            secret: parentNsec,
            salt: deviceId.data(using: .utf8)!,
            info: "mytube:subkey:v1".data(using: .utf8)!,
            outputLength: 32
        )
        return NostrKeyPair(secretKey: derivedSecret)
    }

    // Key package for MLS — must be generated on the device that will join so MDK stores the MLS keys locally.
    func createKeyPackage(for subkey: NostrKeyPair, relays: [String]) async throws -> String {
        return try await mdkActor.createKeyPackage(
            forPublicKey: subkey.publicKey.hex,
            relays: relays
        ).eventJson
    }

    func publishKeyPackage(_ keyPackageJson: String) async throws {
        // Publish to relays via NostrClient
    }

    // Storage
    func storeDeviceSubkey(_ subkey: NostrKeyPair, deviceId: String) throws {
        try keyStore.storeDeviceSubkey(subkey, deviceId: deviceId)
    }

    func fetchCurrentDeviceSubkey() throws -> NostrKeyPair? {
        guard let deviceId = keyStore.fetchDeviceId() else { return nil }
        return try keyStore.fetchDeviceSubkey(deviceId: deviceId)
    }
}
```

### 2.2 MdkActor Modifications

**File**: `Services/Marmot/MdkActor.swift`

Update to use device subkey for MLS operations:

```swift
// The parent nsec signs Nostr events
// The device subkey participates in MLS groups

func createKeyPackage(forDeviceSubkey subkeyPubkey: String, relays: [String]) async throws -> KeyPackageResult {
    // Use subkey instead of parent key for MLS
    return try mdk.createKeyPackage(publicKey: subkeyPubkey, relays: relays)
}
```

### 2.3 Deliverables

- [ ] `Services/Identity/DeviceSubkeyManager.swift`
- [ ] Modify `Services/Marmot/MdkActor.swift`
- [ ] Modify `Services/Marmot/MarmotTransport.swift` (use subkey for MLS)
- [ ] Unit tests for subkey derivation determinism

---

## Phase 3: Device Linking Protocol (v1 - Simple Local QR)

**Goal**: Implement simple local device linking via QR code. Physical proximity = trust.

### Design Rationale (v1 Simplification)

The original design had Nostr-based approval flow (kinds 30081/30082), but this adds complexity without security benefit when:
- Both devices are physically present (same room)
- Parent is holding both devices

For v1, we adopt the simpler model:
- QR contains everything needed to join
- No Nostr round-trip required
- Scanning the QR = approval

This matches the mental model: "Scan this square and you're logged in" (like Netflix).

**Future (v2)**: Add remote linking with Nostr approval for "approve from afar" use case.

### 3.1 DeviceLinkingService

**New file**: `Services/Identity/DeviceLinkingService.swift` (~200 LOC - simplified)

```swift
actor DeviceLinkingService {
    // v1: Simple QR payload - contains everything needed to restore
    struct LinkPayload: Codable {
        let vaultURL: URL
        let vaultKey: Data           // HKDF(nsec) - derived vault key
        let parentPubkey: String     // For verification
        let expiresAt: Date          // QR validity window (5 min)
    }

    // Primary device generates QR
    func generateLinkPayload(
        nsec: Data,
        parentPubkey: String,
        vaultURL: URL
    ) -> LinkPayload {
        let vaultKey = deriveVaultKey(from: nsec, parentPubkey: parentPubkey)

        return LinkPayload(
            vaultURL: vaultURL,
            vaultKey: vaultKey,
            parentPubkey: parentPubkey,
            expiresAt: Date().addingTimeInterval(300)  // 5 min
        )
    }

    func generateQRCode(from payload: LinkPayload) throws -> UIImage {
        let json = try JSONEncoder().encode(payload)
        // Generate QR from JSON
    }

    // New device processes scanned QR
    func processLinkPayload(_ payload: LinkPayload) async throws -> SetupResult {
        guard payload.expiresAt > Date() else {
            throw LinkError.expired
        }

        // 1. Download and decrypt vault
        let vault = try await vaultService.downloadVault(
            from: payload.vaultURL,
            vaultKey: payload.vaultKey
        )

        // 2. Derive nsec from vault key (we need nsec for signing)
        //    Wait - we can't reverse HKDF. We need nsec in the QR.
        //    Let's include it encrypted.

        return SetupResult(vault: vault, needsGroupJoin: true)
    }
}
```

**Important**: We actually need nsec (not just vault key) because the new device needs to:
1. Sign Nostr events
2. Derive its own device subkey

Updated payload:

```swift
struct LinkPayload: Codable {
    let vaultURL: URL
    let nsec: Data               // Parent nsec (this IS the secret being transferred)
    let parentPubkey: String     // For verification
    let expiresAt: Date

    // Vault key can be derived: HKDF(nsec, parentPubkey)
}
```

**Security note**: Yes, the QR contains the nsec. That's intentional. Physical control of both devices during linking is the trust boundary. This is exactly how Signal/WhatsApp device linking works - the QR is the secret.

**User-facing copy**: "Use this when you want MyTube on another iPad in your home. Anyone who scans this code will have full access to your family's account."

### 3.2 No Nostr Events for v1

Device linking is entirely local:
1. Primary shows QR
2. Secondary scans QR
3. Secondary downloads vault, sets up keys
4. Secondary publishes key package
5. Primary detects key package, adds to groups

The only Nostr traffic is the key package (already needed for MLS) and welcome messages.

### 3.3 Deliverables

- [ ] `Services/Identity/DeviceLinkingService.swift` (simplified)
- [ ] QR generation utility
- [ ] Integration tests for link flow

---

## Phase 4: Group Membership Sync

**Goal**: Enable new devices to join all existing MLS groups.

### 4.1 GroupMembershipBackupService

**New file**: `Services/Marmot/GroupMembershipBackupService.swift` (~300 LOC)

```swift
actor GroupMembershipBackupService {
    private let mdkActor: MdkActor
    private let coordinator: GroupMembershipCoordinator

    struct GroupSyncResult {
        let succeeded: [String]      // mlsGroupIds that succeeded
        let failed: [(String, Error)] // mlsGroupIds that failed with error
    }

    // Extract current memberships from MDK
    func extractMemberships() async throws -> [GroupMembershipRecord] {
        let groups = try await mdkActor.getGroups()
        return groups.map { group in
            GroupMembershipRecord(
                mlsGroupId: group.mlsGroupId,
                groupName: group.name ?? "",
                memberPubkeys: group.members.map { $0.publicKey },
                childProfileId: group.childProfileId,
                createdAt: group.createdAt
            )
        }
    }

    // Add new device to all groups (primary device only)
    // Handles partial failures gracefully
    func addDeviceToAllGroups(
        deviceSubkeyPubkey: String,
        keyPackageJson: String,
        progress: @escaping (Int, Int) -> Void  // (current, total)
    ) async -> GroupSyncResult {
        let groups = try? await mdkActor.getGroups() ?? []
        var succeeded: [String] = []
        var failed: [(String, Error)] = []

        for (index, group) in groups.enumerated() {
            progress(index + 1, groups.count)

            do {
                try await coordinator.addMembers(request: AddMembersRequest(
                    mlsGroupId: group.mlsGroupId,
                    keyPackageEventsJson: [keyPackageJson]
                ))
                succeeded.append(group.mlsGroupId)
            } catch {
                failed.append((group.mlsGroupId, error))
                // Continue with other groups - don't fail entire operation
            }
        }

        return GroupSyncResult(succeeded: succeeded, failed: failed)
    }

    // Remove device from all groups (primary device only)
    func removeDeviceFromAllGroups(
        deviceSubkeyPubkey: String,
        progress: @escaping (Int, Int) -> Void
    ) async -> GroupSyncResult {
        let groups = try? await mdkActor.getGroups() ?? []
        var succeeded: [String] = []
        var failed: [(String, Error)] = []

        for (index, group) in groups.enumerated() {
            progress(index + 1, groups.count)

            do {
                try await coordinator.removeMembers(request: RemoveMembersRequest(
                    mlsGroupId: group.mlsGroupId,
                    memberPublicKeys: [deviceSubkeyPubkey]
                ))
                succeeded.append(group.mlsGroupId)
            } catch {
                failed.append((group.mlsGroupId, error))
            }
        }

        return GroupSyncResult(succeeded: succeeded, failed: failed)
    }

    // Retry failed groups (can be called from UI "Retry" button)
    func retryFailedGroups(
        groupIds: [String],
        deviceSubkeyPubkey: String,
        keyPackageJson: String
    ) async -> GroupSyncResult {
        // Similar logic but only for specified groups
    }
}
```

### 4.2 GroupMembershipCoordinator Modifications

**File**: `Services/Marmot/GroupMembershipCoordinator.swift`

```swift
// Add batch methods for device onboarding
func addDeviceToAllGroups(deviceSubkeyPubkey: String, keyPackageJson: String) async throws {
    try await groupMembershipBackupService.addDeviceToAllGroups(
        deviceSubkeyPubkey: deviceSubkeyPubkey,
        keyPackageJson: keyPackageJson
    )
}

func removeDeviceFromAllGroups(deviceSubkeyPubkey: String) async throws {
    try await groupMembershipBackupService.removeDeviceFromAllGroups(
        deviceSubkeyPubkey: deviceSubkeyPubkey
    )
}
```

### 4.3 Deliverables

- [ ] `Services/Marmot/GroupMembershipBackupService.swift`
- [ ] Modify `Services/Marmot/GroupMembershipCoordinator.swift`
- [ ] Integration tests for batch group operations

---

## Phase 5: User Interface

**Goal**: Build the UI flows for device linking and management.

### 5.1 Onboarding Modifications

**File**: `Features/Onboarding/OnboardingView.swift`

Add flow detection:

```swift
enum OnboardingFlow {
    case newHousehold       // First device - create identity
    case addToHousehold     // Link to existing - scan QR
}

struct OnboardingView: View {
    @State private var flow: OnboardingFlow?

    var body: some View {
        if flow == nil {
            // Show choice: "Create New" vs "Add to Existing"
            OnboardingChoiceView(selectedFlow: $flow)
        } else if flow == .newHousehold {
            // Existing onboarding flow
            NewHouseholdOnboardingView()
        } else {
            // New: scan QR to link
            DeviceLinkScannerView()
        }
    }
}
```

### 5.2 DeviceLinkScannerView

**New file**: `Features/Onboarding/DeviceLinkScannerView.swift` (~150 LOC)

```swift
struct DeviceLinkScannerView: View {
    @StateObject private var viewModel = DeviceLinkScannerViewModel()

    var body: some View {
        VStack {
            switch viewModel.state {
            case .scanning:
                CameraQRScannerView(onScan: viewModel.handleScannedQR)
                Text("Scan the QR code on your other device")

            case .requesting:
                ProgressView("Requesting access...")

            case .awaitingApproval:
                Text("Waiting for approval on your other device...")

            case .downloading:
                ProgressView("Downloading your data...")

            case .joiningGroups(let progress):
                ProgressView("Joining circles... \(progress.current)/\(progress.total)")

            case .complete:
                Text("You're all set!")

            case .error(let message):
                Text("Error: \(message)")
                Button("Try Again") { viewModel.reset() }
            }
        }
    }
}
```

### 5.3 AddDeviceView

**New file**: `Features/ParentZone/AddDeviceView.swift` (~150 LOC)

```swift
struct AddDeviceView: View {
    @StateObject private var viewModel = AddDeviceViewModel()

    var body: some View {
        VStack {
            switch viewModel.state {
            case .generating:
                ProgressView("Generating link...")

            case .showingQR(let qrImage):
                Image(uiImage: qrImage)
                    .resizable()
                    .frame(width: 200, height: 200)
                Text("Scan this code with your new device")
                Text("Expires in \(viewModel.timeRemaining)")

            case .pendingApproval(let request):
                Text("New device wants to connect:")
                Text(request.deviceName)
                HStack {
                    Button("Deny") { viewModel.denyRequest() }
                    Button("Approve") { viewModel.approveRequest() }
                }

            case .addingToGroups:
                ProgressView("Adding device to your circles...")

            case .complete:
                Text("Device added successfully!")
            }
        }
    }
}
```

### 5.4 DeviceManagementView

**New file**: `Features/ParentZone/DeviceManagementView.swift` (~200 LOC)

```swift
struct DeviceManagementView: View {
    @StateObject private var viewModel = DeviceManagementViewModel()

    var body: some View {
        List {
            Section("Your Devices") {
                ForEach(viewModel.devices) { device in
                    DeviceRow(device: device, isCurrentDevice: device.id == viewModel.currentDeviceId)
                }
            }

            if viewModel.isPrimaryDevice {
                Section {
                    NavigationLink("Add Device") {
                        AddDeviceView()
                    }
                }
            }
        }
        .navigationTitle("Devices")
    }
}

struct DeviceRow: View {
    let device: DeviceRecord
    let isCurrentDevice: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(device.deviceName)
                if device.isPrimary {
                    Text("Primary")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            if isCurrentDevice {
                Text("This device")
                    .foregroundColor(.secondary)
            }
        }
    }
}
```

### 5.5 ParentZoneView Modifications

**File**: `Features/ParentZone/ParentZoneView.swift`

Add Devices section:

```swift
Section("Devices") {
    NavigationLink {
        DeviceManagementView()
    } label: {
        Label("Manage Devices", systemImage: "ipad.and.iphone")
    }
}
```

### 5.6 Deliverables

- [ ] Modify `Features/Onboarding/OnboardingView.swift`
- [ ] `Features/Onboarding/OnboardingChoiceView.swift`
- [ ] `Features/Onboarding/DeviceLinkScannerView.swift`
- [ ] `Features/ParentZone/AddDeviceView.swift`
- [ ] `Features/ParentZone/DeviceManagementView.swift`
- [ ] Modify `Features/ParentZone/ParentZoneView.swift`

---

## Phase 6: iCloud Keychain Backup

**Goal**: Automatically backup parent nsec to iCloud Keychain so recovery "just works" on new devices.

### 6.1 Why This Matters

Without iCloud Keychain:
- Parent loses device → loses nsec → loses everything
- Parent gets new iPad → must manually enter nsec (they won't have it)
- Result: angry parents, lost family memories, bad reviews

With iCloud Keychain:
- Parent gets new iPad → signs into iCloud → nsec automatically available
- Recovery is invisible, "it just works"
- Matches Apple's UX expectations

### 6.2 Implementation

**Modify**: `Services/KeychainKeyStore.swift`

```swift
// New: iCloud-synced nsec storage
private static let iCloudNsecKey = "parent.signing.icloud"

func storeNsecToiCloud(_ nsec: Data) throws {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.mytube.keys.icloud",
        kSecAttrAccount as String: Self.iCloudNsecKey,
        kSecValueData as String: nsec,
        kSecAttrSynchronizable as String: true,  // THIS enables iCloud sync
        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
    ]

    let status = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess || status == errSecDuplicateItem else {
        throw KeychainError.storeFailed(status)
    }
}

func fetchNsecFromiCloud() -> Data? {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.mytube.keys.icloud",
        kSecAttrAccount as String: Self.iCloudNsecKey,
        kSecAttrSynchronizable as String: true,
        kSecReturnData as String: true
    ]

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    guard status == errSecSuccess, let data = result as? Data else {
        return nil
    }
    return data
}

func removeNsecFromiCloud() throws {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.mytube.keys.icloud",
        kSecAttrAccount as String: Self.iCloudNsecKey,
        kSecAttrSynchronizable as String: true
    ]

    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
        throw KeychainError.deleteFailed(status)
    }
}
```

### 6.3 Onboarding Flow Integration

**Modify**: `Features/Onboarding/OnboardingView.swift`

After generating identity:

```swift
// During new user onboarding, after generating nsec
func completeIdentitySetup() async throws {
    // 1. Generate and store locally (existing)
    let parentKey = try identityManager.generateParentIdentity()

    // 2. Backup to iCloud (new)
    try keyStore.storeNsecToiCloud(parentKey.secretKey)

    // 3. Show confirmation
    // "Your account is backed up to iCloud. If you get a new device,
    //  just sign into iCloud and MyTube will restore automatically."
}
```

### 6.4 Recovery Flow Integration

**Modify**: `Features/Onboarding/OnboardingView.swift`

On app launch, check for iCloud nsec:

```swift
func checkForExistingAccount() async -> OnboardingFlow {
    // 1. Check local Keychain first
    if let localNsec = keyStore.fetchKeyPair(role: .parentSigning) {
        return .existingLocal
    }

    // 2. Check iCloud Keychain
    if let iCloudNsec = keyStore.fetchNsecFromiCloud() {
        // Found! Restore automatically
        return .restoreFromiCloud(nsec: iCloudNsec)
    }

    // 3. No existing account
    return .newUser
}
```

### 6.5 User Consent & Transparency

Show during onboarding:

```
┌─────────────────────────────────────────┐
│                                         │
│  Keep Your Family's Videos Safe         │
│                                         │
│  We'll backup your account key to       │
│  iCloud so you never lose access to     │
│  your family's videos.                  │
│                                         │
│  ✓ Encrypted end-to-end                 │
│  ✓ Only accessible on your devices      │
│  ✓ Automatically restored on new iPads  │
│                                         │
│  [Continue with iCloud Backup]          │
│                                         │
│  Skip for now (not recommended)         │
│                                         │
└─────────────────────────────────────────┘
```

If they skip, show a persistent reminder in ParentZone.

### 6.6 Deliverables

- [ ] Modify `Services/KeychainKeyStore.swift` (iCloud sync methods)
- [ ] Modify `Features/Onboarding/OnboardingView.swift` (auto-backup + consent UI)
- [ ] Add iCloud recovery detection on app launch
- [ ] Add "Backup Status" indicator in ParentZone settings
- [ ] Unit tests for iCloud Keychain operations

---

## Phase 7: Integration & Polish

**Goal**: Wire everything together and handle edge cases.

### 7.1 AppEnvironment Modifications

**File**: `AppEnvironment.swift`

```swift
// Add new services
let identityVaultService: IdentityVaultService
let deviceLinkingService: DeviceLinkingService
let deviceSubkeyManager: DeviceSubkeyManager
let groupMembershipBackupService: GroupMembershipBackupService

// Add device role check
var isPrimaryDevice: Bool {
    keyStore.fetchIsPrimary()
}

// Initialize in init()
self.identityVaultService = IdentityVaultService(
    storageClient: storageClient,
    cryptoService: cryptoEnvelopeService
)
self.deviceSubkeyManager = DeviceSubkeyManager(
    keyStore: keyStore,
    mdkActor: mdkActor
)
// ... etc
```

### 7.2 Primary Device Role Enforcement

Disable admin actions on secondary devices:

```swift
// In GroupMembershipCoordinator
func createGroup(request: CreateGroupRequest) async throws {
    guard appEnvironment.isPrimaryDevice else {
        throw GroupError.adminOperationRequiresPrimaryDevice
    }
    // ... existing logic
}
```

### 7.3 Vault Sync on Changes

Update vault when state changes:

```swift
// After creating a group
func createGroup(request: CreateGroupRequest) async throws {
    // ... create group ...

    // Update vault
    try await identityVaultService.updateVault { vault in
        vault.groupMemberships.append(newMembership)
    }
}

// After adding a child profile
func createChildProfile(name: String, theme: String) async throws {
    // ... create profile ...

    // Update vault
    try await identityVaultService.updateVault { vault in
        vault.childProfiles.append(childBackup)
    }
}
```

### 7.4 Deliverables

- [ ] Modify `AppEnvironment.swift`
- [ ] Add role enforcement to coordinator methods
- [ ] Add vault sync triggers throughout app
- [ ] End-to-end integration tests
- [ ] Update documentation

---

## Estimated Scope Summary

| Component | New Code | Modified Code | Complexity |
|-----------|----------|---------------|------------|
| IdentityVaultService | ~500 LOC | - | Medium |
| DeviceLinkingService | ~200 LOC | - | Low (simplified for v1) |
| DeviceSubkeyManager | ~300 LOC | - | Medium |
| GroupMembershipBackupService | ~350 LOC | - | Medium |
| iCloud Keychain integration | - | ~150 LOC | Low |
| KeychainKeyStore changes | - | ~100 LOC | Low |
| IdentityManager changes | - | ~150 LOC | Medium |
| MdkActor changes | - | ~100 LOC | High |
| GroupMembershipCoordinator changes | - | ~150 LOC | High |
| AppEnvironment changes | - | ~50 LOC | Low |
| UI: OnboardingView changes | - | ~200 LOC | Medium |
| UI: DeviceLinkScannerView | ~150 LOC | - | Medium |
| UI: AddDeviceView | ~150 LOC | - | Medium |
| UI: DeviceManagementView | ~200 LOC | - | Low |
| UI: ParentZoneView changes | - | ~50 LOC | Low |
| UI: iCloud Backup consent | ~100 LOC | - | Low |
| **Total** | **~1950 LOC** | **~950 LOC** | |

---

## Future Enhancements (Not in v1 Scope)

### High Priority (should do soon after v1)
- **Recovery sheet generation** - Printable PDF with QR code for nsec backup (alternative to iCloud)
- **"Make this device primary" UI** - For when primary device is lost/replaced

### Medium Priority
- **Remote device linking (v2)** - Nostr-based approval flow (kinds 30081/30082) for "approve from afar"
- **Device limit enforcement** - Cap linked devices per household
- **Vault versioning/merge** - Proper conflict resolution when multiple devices update vault

### Lower Priority
- Secure Enclave for parent key storage
- Emergency recovery via trusted family member (escrow key share)
- Automatic primary device failover
- "Migrate to new parent keypair" for key rotation after compromise
- Cross-family device visibility
