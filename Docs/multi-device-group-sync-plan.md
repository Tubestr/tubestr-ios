# Multi-Device Group Sync Plan

## Problem
When a parent creates a Marmot group on Device 1, Device 2 (recovered with same nsec) never learns about it because:
- The creator doesn't receive a welcome for groups they create
- MDK state is local to each device
- MDK cannot be modified

## Solution: Group Backup + Semi-Automatic Re-Join

### Overview
1. **Backup**: When groups are created, back up metadata to Nostr (encrypted to parent)
2. **Detect**: On app launch after recovery, compare backup vs local MDK groups
3. **Prompt**: Show user "X groups need to sync" with a single "Sync All" action
4. **Re-join**: Trigger re-invites for missing groups; user accepts welcomes

### Implementation

#### 1. GroupMembershipBackupService (~200 lines)
**File**: `MyTube/Services/GroupMembershipBackupService.swift`

Pattern after `ChildKeyBackupService.swift`:
- Event kind: 30079 (NIP-78 app-specific data)
- D-tag: `"mytube:group_memberships"`
- Encrypted: NIP-44 to parent's own pubkey

**Backup structure**:
```swift
struct GroupMembershipBackup: Codable {
    let mlsGroupId: String
    let nostrGroupId: String
    let name: String
    let description: String
    let relays: [String]
    let createdAt: Double
}
```

**Methods**:
- `publishBackup()` - Called after group creation
- `fetchBackup()` - Called during recovery/app launch
- `getMissingGroups()` - Compare backup vs `mdkActor.getGroups()`

#### 2. Trigger Backup on Group Creation
**File**: `MyTube/Services/Marmot/GroupMembershipCoordinator.swift`

After successful `createGroup()`, call `groupMembershipBackupService.publishBackup()`.

#### 3. Re-Join Flow
**File**: `MyTube/Features/ParentZone/ParentZoneViewModel.swift`

Add method `rejoinMissingGroups()`:
1. For each missing group, create a fresh key package for parent
2. Call `addMembers()` on any device that HAS the group (could be same device if it's Device 1)
3. Publish welcome to relays
4. Device 2 receives welcome via existing subscription
5. User accepts via existing pending welcomes flow

**Challenge**: Device 2 doesn't have the group, so it can't call `addMembers()`. Need Device 1 (or another device with the group) to do it.

**Solution**: The re-join request needs to be published to Nostr so Device 1 can pick it up.

#### 4. Re-Join Request Protocol
New event kind for re-join requests:
- Kind: 30080 (or similar)
- Content: Encrypted request containing parent's fresh key package + target group nostrGroupId
- P-tag: Parent's own pubkey (so all their devices see it)

**Flow**:
1. Device 2 detects missing group from backup
2. Device 2 creates key package and publishes re-join request
3. Device 1 (subscribed to parent's events) receives request
4. Device 1 calls `addMembers()` with the key package
5. Welcome is published to relays
6. Device 2 receives and accepts welcome

#### 5. UI Changes
**File**: `MyTube/Features/ParentZone/ParentZoneView.swift`

Add banner/alert when missing groups detected:
- "3 groups need to sync to this device"
- "Sync Now" button triggers re-join flow
- Shows progress as welcomes are received/accepted

### Files to Modify

| File | Changes |
|------|---------|
| `Services/GroupMembershipBackupService.swift` | NEW - Backup service |
| `Services/Marmot/GroupMembershipCoordinator.swift` | Call backup after createGroup |
| `Features/ParentZone/ParentZoneViewModel.swift` | Add missing group detection + re-join logic |
| `Features/ParentZone/ParentZoneView.swift` | Add sync prompt UI |
| `Services/Sync/SyncCoordinator.swift` | Subscribe to re-join request events |
| `AppEnvironment.swift` | Wire up new service |

### Complexity
- ~400 lines new code
- Follows existing patterns (ChildKeyBackupService, welcome flow)
- No MDK changes required
