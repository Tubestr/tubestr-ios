# CLAUDE NOTES — MyTube (iPad SwiftUI, Parent-Only MDK Groups)

This file is a quick orientation to the current architecture and rules. It mirrors the latest docs refresh (parent-only keys, lazy group creation, Marmot/MDK-only messaging).

## Core Architecture
- iPad-first SwiftUI app. Source under `MyTube/`; features in `MyTube/Features/*`, domain in `MyTube/Domain`, services in `MyTube/Services`, shared UI in `MyTube/SharedUI`.
- Layers: SwiftUI features → shared UI → domain models/helpers → services (Marmot/MDK, Nostr, MinIO, crypto) → persistence (Core Data, MDK SQLite, file system via `StoragePaths`, Keychain).
- `AppEnvironment` wires dependencies into SwiftUI scenes via `@EnvironmentObject`.

## Identity & Groups (Current Model)
- Parents only have Nostr keys; stored in Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`). Children have no keys or delegations (stubs only).
- Groups are parent-only MDK/MLS groups. Each child profile can reference one `mlsGroupId`.
- Group creation is lazy: first cross-family connection creates the group with ≥2 parent members. No groups during onboarding.
- All Marmot messages are signed by the parent key; child attribution lives in payload fields (`child_name`, `child_profile_id`, `owner_child` = profile UUID).

## Messaging & Protocol
- Transport is MDK over Nostr (Marmot kinds 443/444/445/1059, message kinds 4543–4547). Gift wraps (NIP-59) only for welcomes.
- Payloads: video_share, video_revoke, video_delete, like, report. Parent-signed only; children never sign.
- Replaceables: only tombstones (30302) remain; follow pointers are removed.
- Media plane: XChaCha20-Poly1305 encrypted blobs in MinIO; no per-recipient wrapping (MLS handles keys).

## Storage & Paths
- Core Data for app state (`VideoEntity`, `RemoteVideoEntity`, `ProfileEntity`, etc.).
- MDK SQLite at `Application Support/MyTube/mdk.sqlite` (via `MdkActor`).
- Files under `Application Support/MyTube/{Media,Thumbs,Edits}` with `.completeFileProtection`, split by profile UUID; shared media under `/Shared`.
- Keychain holds parent keypair only.

## Key Services & Coordinators
- `MdkActor`, `MarmotTransport`, `MarmotShareService`, `MarmotProjectionStore`, `GroupMembershipCoordinator`, `VideoShareCoordinator/Publisher`, `RemoteVideoDownloader`, `SyncCoordinator`.
- `SyncCoordinator` subscribes to Marmot kinds and tombstones, drives MDK ingestion, and keeps Core Data projections fresh.

## Build & Test Commands
- Build: `xcodebuild -scheme MyTube -destination 'platform=iOS Simulator,name=iPad mini (A17 Pro)' build`
- Tests: `xcodebuild test -scheme MyTube -destination 'platform=iOS Simulator,name=iPad mini (A17 Pro)'`
- Optional lint: `swift run swiftlint`
- Optional format: `swift-format --configuration .swift-format.json --recursive MyTube`

## Current Priorities (from docs)
- Harden telemetry/backpressure for Marmot publishing; ensure MDK projections refresh after resumes.
- Add Secure Enclave/rotation/recovery UX for the parent key; clean remaining delegation stubs.
- Finish premium paywall (StoreKit 2) and remote share UX (download/decrypt, revoke/delete flows).
- Add pending-action queue and offline reconciliation for SyncCoordinator/Marmot events.

## Reference Docs
- `Docs/Architecture.md` — layer overview, parent-only groups.
- `Docs/ParentOnlyGroupsRefactor.md` — rationale and migration notes.
- `Docs/MyTubeProtocolSpec.md` — payload schemas (parent-only), MinIO contracts, flows.
- `Docs/MDKRefactorPlan.md` — MDK migration plan/status.
- `Docs/MyTubeImplementationPlan.md` — gaps, roadmap, immediate tasks.
