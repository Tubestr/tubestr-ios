# Child Nostr Identity Plan (Superseded)

_Status: Replaced by parent-only groups (Nov 2025). Children no longer have Nostr keys._

This document now records why the original child-key plan was abandoned and how the current identity model works. The previous content (child npubs/nsecs, NIP-44 backups, child key packages) is intentionally removed to avoid drift.

---

## Why We Dropped Child Nostr Identities

- **Safety & compliance**: Keeping children off the network simplifies COPPA/SRL considerations and avoids exposing child keys to relays.
- **Simplicity**: Eliminates delegation issuance/validation, key backup, and child key package distribution.
- **Reliability**: MDK groups operate only with parent keys; fewer identities means fewer onboarding and recovery edge cases.
- **Product clarity**: Parents control all sharing; children remain local profiles used for attribution only.

---

## Current Identity Model (Authoritative)

- **Parents only have keys**: A single Nostr keypair per household lives in Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`).
- **Children are local profiles**: UUID, name, theme, avatar. No Nostr keys, no delegations, no relay presence.
- **Group membership**: Only parent identities join Marmot/MDK groups. Child profiles are associated with at most one `mlsGroupId` (stored on the profile) for sharing.
- **Authorship**: All Marmot messages are signed by the parent key. Child attribution is embedded in the payload (`child_name`, `child_profile_id`, `owner_child` as profile UUID).
- **Group creation timing**: We create a group lazily when the first cross-family connection is made (MLS requires ≥2 members). Onboarding no longer creates groups up front.

---

## Impacted / Removed Work

- No `ChildKeyBackupService`, `ChildMetadataPublisher`, or child key storage in `KeychainKeyStore`.
- `IdentityManager` no longer generates or restores child keypairs; any delegated paths remain as stubs for backward compatibility only.
- `SyncCoordinator` and `NostrEventReducer` ignore child key backups and child kind 0 events.
- Invite flows only exchange parent key packages; welcomes add parent members, not children.

---

## What To Implement Going Forward

1. Keep the identity stack parent-only; remove remaining references to child npubs/nsecs as we touch code.
2. Ensure all payloads that reference children use profile UUIDs and display names only.
3. Maintain the lazy group creation rule (first connection creates the group, 2+ parent members).
4. Keep delegation helpers stubbed for compatibility but unused.

See `Docs/ParentOnlyGroupsRefactor.md` and `Docs/Architecture.md` for the end-to-end architecture that supersedes this plan.
