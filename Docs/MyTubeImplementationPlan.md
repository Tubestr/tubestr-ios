# MyTube Implementation Plan

This plan translates the approved protocol and product spec into actionable engineering work. It captures the current application state (as of commit time) and outlines the roadmap Codex should follow to deliver the MVP.

---

## 1. Current State vs. Spec (Gap Analysis)

| Area | Spec Expectation | Current Implementation | Gaps / Risks |
| ---- | ---------------- | ---------------------- | ------------ |
| **Networking & Relays** | Full Nostr client (publish/subscribe, relay management, replaceables) with durable filters | `URLSessionNostrClient` now manages retry/backoff, health snapshots, and resubscription across relays | Persist subscription filters, surface latency metrics, add replaceable dedupe/storage |
| **Crypto Key Management** | Parent-only keypair in Keychain (Secure Enclave optional); no child keys or delegations required (stubs only) | `KeychainKeyStore` + `IdentityManager` generate/store the parent key, support QR/clipboard onboarding; child/delegation paths removed or stubbed | Add Secure Enclave/rotation UX, recovery flows, and backup reminders |
| **Encrypted Messaging** | MDK/Marmot messaging with parent-only groups, MLS welcomes/commits, and rumor fan-out; lazy group creation when 2+ parents | `MdkActor`, `GroupMembershipCoordinator`, `MarmotTransport`, `MarmotShareService`, and `MarmotProjectionStore` drive group ops plus shares/likes/reports (gift-wrapped via NIP-59) with `mlsGroupId` on profiles | Harden telemetry/backpressure, background refresh coverage, Safety HQ group wiring, and error surfacing |
| **Media Encryption & Upload** | XChaCha20-Poly1305 media encryption, MinIO helper API, upload/delete flow | `CryptoEnvelopeService` handles media encryption & gift-wrap sealing; `VideoSharePublisher` + `MarmotShareService` upload blobs and publish Marmot messages | Harden upload error handling, add download helpers, and wire UI workflows plus revoke fan-out |
| **Sharing Graph** | MDK group membership is the graph; each profile tracks a single `mlsGroupId`; no follow replaceables/pointers | RelationshipStore removed; GroupMembershipCoordinator + MDK manage invites/welcomes; Parent Zone surfaces group state/diagnostics; Core Data mirrors `mlsGroupId` usage | Pending-action queue, conflict resolution, better UI for membership states, clean remaining follow/delegation remnants |
| **Premium Paywall** | StoreKit subscription gating cloud features | No StoreKit code | Add StoreKit 2 flow, subscription state persistence, gating in UI/services |
| **UI/UX** | Relay management, group welcome/accept flows, share/revoke flows, premium onboarding, safety disclosures | Feed shows local shelves plus "Shared With You" via Marmot projections; Parent Zone exposes relay diagnostics, group approvals/welcomes, revoke/block, share stats | Add premium flows, remote playback/download UX, richer share history/revoke controls, and safety disclosures |
| **Background Sync** | Relay subscriptions for Marmot kinds + tombstones, cache persistence, offline handling, delete/revoke compliance | Sync pipeline writes remote video state via Marmot projection; relay health exposed to UI | Persist subscriptions, add offline reconciliation, purge local caches on delete/revoke, ensure MDK projections refresh after resumes |
| **Testing** | Unit tests for crypto, Marmot projection, MinIO client, paywall; UI tests for group invite/share/delete flows | Current tests focus on local ranking & storage | Expand coverage, add networking/crypto stubs, UI automation for group welcome/share/delete flows |

Supporting files reviewed: `AppEnvironment.swift`, `StoragePaths.swift`, `Services/VideoLibrary.swift`, `Services/ParentAuth.swift`, `Domain/RankingEngine.swift`, `Features/*` SwiftUI views.

---

## 2. Implementation Roadmap

1. **Foundational Services**
   - Add `NostrClient` with relay management, publish/subscribe pipeline, durable storage of replaceables (extend existing `URLSessionNostrClient` scaffolding).
   - Harden `KeychainKeyStore` for the parent-only keypair (Secure Enclave optional) with rotation/export UX. _Status: IdentityManager + onboarding/Parent Zone cover parent generation/import and QR export; Secure Enclave + rotation/recovery flows still pending._
   - Create `CryptoEnvelopeService` for XChaCha20 media encryption, key wrapping/unwrapping, and NIP-59 gift-wrap helpers. _Status: service implemented and integrated; unit tests pending._

2. **Data Model Extensions**
   - Keep Core Data entities for `RemoteVideo`, `PendingAction`, and MDK projections (groups/memberships) aligned with parent-only groups; remove or ignore deprecated follow entities.
   - Provide migration helpers and background fetch APIs in the service layer (`GroupMembershipStore`, `ShareStore`). _Status:_ Remote video entities exist and are fed by Marmot projection; pending-action queue and membership projection hardening still needed.

3. **MinIO Integration**
   - Introduce `MinIOClient` to hit `/upload/init`, signed PUT/GET, `/upload/commit`, and `/media` DELETE.
   - Add retry/backoff and exponential fallback; persist keys for delete fan-out. _Status: helper client + share publisher actor implemented; Parent Zone share sheet now drives outbound uploads; retries plus download/delete wiring still pending._

4. **Relay Sync Engine**
   - Complete `SyncCoordinator` (background actor) so it:
     - Maintains Marmot + replaceable subscriptions (key packages, welcomes, group commits, rumors, tombstones) across launches.
     - Validates signatures (parent-only) and dedupes metadata/replaceables via `NostrEventReducer` with Marmot projection online.
     - Persists reducer output to Core Data on the main actor and informs dependent view models.
    - Add rate limiting, telemetry hooks, and relay health reporting surfaced in Parent Zone. _Status: health UI is live; need subscription persistence/dedupe hardening and offline reconciliation + telemetry._

5. **UI Enhancements**
   - Onboarding: role selection and parent setup/import (no child-key import); keep group creation lazy until a remote parent is added. _Status: parent onboarding + diagnostics view are live; need clearer prompts when `mlsGroupId` is missing._
   - Settings/Parent Zone: relay editor, Secure Enclave status, paywall messaging.
   - Parent Zone: approvals dashboard (group welcomes), share history, revoke/delete actions, enhanced diagnostics. _Status: Marmot approvals/revoke/block + stats live; history/download UX remains._
   - Feed: integrate remote shares, show download/decrypt states, purge on delete. _Status: "Shared With You" shelf live via Marmot projection; playback/download UX still TBD._
   - Capture/Editor: premium gating for cloud features, status indicators during upload/encrypt.
   - Player/Editor modals already widened; add share/revoke buttons per spec.

6. **Premium Paywall**
   - Implement StoreKit 2 subscription flow (`$20/year`), receipt validation (local), grace periods.
   - Gate MinIO and share features; expose upgrade CTA.

7. **Safety & Compliance**
   - Add "How MyTube protects your child" explainer.
   - Implement report/block UI backed by `MarmotShareService` (plus the forthcoming safety-group channel) so moderation never falls back to legacy direct messaging.

8. **Testing & QA**
   - Unit tests for crypto utilities, Marmot projection/gift-wrap handling, MinIO client, relay directory, remote video store, and sync reducers.
   - UI tests for group invite/accept, share/decrypt playback, delete propagation, and relay management.
   - Stress tests for large remote graph (cached data) and offline delete propagation.

9. **Documentation & Dev Tooling**
   - Update `AGENTS.md` with relay setup, MinIO credentials, development workflows.
   - Provide scripts for seeding relays, mocking upload endpoints, and running local MinIO.

Each milestone should land via atomic commits (per repository guidelines) with proof of tests (`xcodebuild test` and relevant suites). Prioritize delivering a functioning local experience while layering cloud capabilities carefully to preserve offline-first behavior.

---

## 3. Immediate Follow-up Tasks

- Persist relay subscription filters on disk, dedupe replaceables, and emit health telemetry (latency, consecutive failures) from `URLSessionNostrClient`.
- Add deterministic unit tests for `CryptoEnvelopeService` covering XChaCha media encryption, key wrapping, and gift-wrap framing edge cases.
- Build pending-action queue + retry/backpressure for Marmot publishing; reconcile duplicate pointer records and ensure membership changes (welcomes/commits) propagate before shares.
- Add Secure Enclave support and key rotation/recovery UX for the parent key; clean up remaining delegation UX stubs.
- Finalize `SyncCoordinator` so it persists subscriptions, restores them on launch, and invalidates feeds/player/editor when remote data changes; consider background projection refresh for suspended gaps and MDK projection refresh on resume.
- Surface `RelayDirectory` management in Parent Zone settings (add/remove/toggle relays) with health indicators, and ensure `SyncCoordinator` refreshes subscriptions on edits.
- Finish remote share UX: enable decrypt/download actions from the "Shared With You" shelf and propagate delete/revoke handling into Player/Editor flows.
- Expand Parent Zone share/history UX with recipient presets, share history, revoke/delete fan-out, and download hooks into player/editor.
- Ship premium paywall (StoreKit 2) and gate cloud features accordingly.
