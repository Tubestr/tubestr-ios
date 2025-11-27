# Children as Nostr Identities with Marmot Group Membership

## Overview

Give children real Nostr keys (npub/nsec), publish their metadata via kind 0, and add them to the family Marmot MLS group. Child nsecs are backed up via NIP-44 encrypted events to the parent's own pubkey, enabling multi-device recovery.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                   PARENT (Nostr Identity)                       │
│  ├─ keyPair (nsec/npub)                                        │
│  ├─ Kind 0: name, picture, mytube_wrap_key                     │
│  └─ Kind 30078: NIP-44 encrypted child nsecs (backup)          │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ Creates & Manages
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│           MARMOT GROUP (MLS Family Group)                       │
│  ├─ Members: Parent + Child(s) + Remote Parent + Remote Child   │
│  ├─ All members can decrypt group messages                     │
│  └─ Key packages fetched from relays (kind 443)                │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ Contains
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│          CHILDREN (Nostr Identities)                            │
│  ├─ keyPair (nsec/npub) - random, backed up encrypted          │
│  ├─ Kind 0: name, mytube_parent (parent npub reference)        │
│  └─ Kind 443: Key package for Marmot group membership          │
└─────────────────────────────────────────────────────────────────┘
```

## Child Key Management

### Generation
- Generate random Nostr keypair per child via `NostrSDK.Keys.generate()`
- Store nsec in Keychain (keyed by child UUID)

### NIP-44 Backup to Self
Publish encrypted backup so any device with parent nsec can recover child keys:

```swift
// Kind 30078 = NIP-78 Application-specific data (replaceable)
struct ChildKeyBackup: Codable {
    let childId: String        // UUID
    let childName: String
    let nsec: String           // bech32 nsec
    let createdAt: Double
}

// Event structure
// kind: 30078
// tags: [["d", "mytube:child_keys"]]
// content: NIP-44 encrypted JSON array of ChildKeyBackup
// pubkey: parent pubkey (to self)
```

### Recovery Flow (New Device)
1. Parent imports nsec on new device
2. Fetch kind 30078 with `d` tag `mytube:child_keys` from relays
3. Decrypt content with NIP-44 using parent keys (to self)
4. Parse `[ChildKeyBackup]` and restore to Keychain
5. Fetch child kind 0 events to populate metadata

## Kind 0 for Children

Minimal metadata published under child's npub:

```json
{
  "name": "Emma",
  "mytube_parent": "npub1parent..."
}
```

- No picture/about (keep lightweight)
- `mytube_parent` links child to parent for discovery

## Marmot Group Membership

### Adding Children to Groups
When creating/joining a Marmot group:
1. Publish child's key package (kind 443) to relays
2. Add child as member via `GroupMembershipCoordinator.addMembers()`
3. Child can now decrypt all group messages

### Invite Flow Update
When connecting families:
1. Scan QR with parent npub (existing flow)
2. Fetch parent's key package from relay
3. Also fetch child key packages (children listed in kind 30078 backup, decrypted)
4. Create group with parent + children as members

### New Child After Group Exists
**Decision: Require re-invite** - Children created after a group exists are NOT auto-added. The other family must send a fresh invitation to include the new child. This keeps group membership explicit and consent-based.

## Rankings & Watch History

**Decision: Skip sync** - Rankings stay device-local. Only profile metadata syncs.

## New Files

| File | Purpose |
|------|---------|
| `Services/ChildKeyBackupService.swift` | Publish/fetch NIP-44 encrypted child keys |
| `Services/ChildMetadataPublisher.swift` | Publish kind 0 for children |

## Files to Modify

| File | Changes |
|------|---------|
| `IdentityManager.swift` | Restore `keyPair` on ChildIdentity, add nsec generation |
| `KeychainKeyStore.swift` | Store/fetch child keypairs (keyed by UUID) |
| `CryptoEnvelopeService.swift` | Already has NIP-44 support |
| `ParentZoneViewModel.swift` | Call backup service on child create/edit/delete |
| `SyncCoordinator.swift` | Subscribe to kind 30078 for child key backup |
| `NostrEventReducer.swift` | Handle kind 30078 backup events |
| `KeyPackageDiscovery.swift` | Publish key packages for children |
| `GroupMembershipCoordinator.swift` | Add children when creating/joining groups |

## Event Kinds Used

| Kind | Purpose |
|------|---------|
| 0 | Child profile metadata |
| 443 | Key packages (parent + children) |
| 30078 | Encrypted child key backup (NIP-78) |

## Implementation Phases

### Phase 1: Child Key Infrastructure ✅
- [x] Restore `keyPair` on `ChildIdentity`
- [x] Generate random keypair on child creation
- [x] Store in Keychain via `KeychainKeyStore`
- [x] Add `ChildKeyBackupService` for NIP-44 backup

### Phase 2: Kind 0 Publishing ✅
- [x] Add `ChildMetadataPublisher` for minimal kind 0
- [x] Publish on child create/edit
- [x] Subscribe to child kind 0 in `SyncCoordinator`

### Phase 3: Marmot Integration ✅
- [x] Publish child key packages (kind 443) when children are created
- [x] Add local children to groups during group creation
- [x] Update invite flow (v4) to include all children's public keys
- [x] Fetch and add remote children's key packages during invite flow

### Phase 4: Recovery Flow ✅
- [x] Fetch kind 30078 on parent key import
- [x] Decrypt and restore child nsecs
- [x] Create profiles for recovered children
- [x] Fetch child kind 0 for metadata via SyncCoordinator

## Testing

- Unit: NIP-44 encrypt/decrypt, key backup serialization
- Integration: Child key backup round-trip via relay
- E2E: Parent imports key on new device, children restored
