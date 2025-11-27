# Blossom Migration Plan

## Executive Summary

Migrate MyTube from MinIO/S3 presigned URLs to Blossom blob storage for better Nostr ecosystem compatibility. MDK already has substantial Blossom integration (MIP-01, MIP-04) that can be leveraged.

---

## Current vs Target Architecture

### Current Flow
```
iOS App → XChaCha20-Poly1305 encrypt → presigned URL from backend → upload to MinIO/S3
```

### Target Flow (Option A - Recommended)
```
iOS App → MIP-04 encrypt via MDK → direct Blossom upload → store hash in message
```

### Target Flow (Option B - Simpler)
```
iOS App → XChaCha20-Poly1305 encrypt → direct Blossom upload → store hash in message
```

---

## Decision: Option B - Keep Current Encryption

**DECIDED**: Keep XChaCha20-Poly1305 encryption, swap storage layer to Blossom.

| Aspect | Value |
|--------|-------|
| **Blossom Server** | `https://blossom.tubestr.app` (self-hosted) |
| **Encryption** | XChaCha20-Poly1305 (24-byte nonce) - unchanged |
| **Key derivation** | Random per-video keys - unchanged |
| **Backend** | Keep for quotas, IAP, auth |
| **Thumbnails** | Unencrypted (unchanged) |

---

## Phase 1: Add Blossom Client to iOS App

### New Files to Create

#### 1. `MyTube/Services/Storage/BlossomClient.swift`
```swift
// Implements MediaStorageClient protocol for Blossom servers
// - NIP-98 authentication for uploads
// - SHA256 hash-based addressing
// - BUD (Blossom Upload Descriptor) support
```

**Key responsibilities:**
- Upload encrypted blobs to Blossom server
- Download by SHA256 hash
- Delete with derived keypair (MIP-01 style)
- Support multiple Blossom servers (redundancy)

#### 2. `MyTube/Services/Storage/BlossomConfig.swift`
```swift
// Configuration for Blossom servers
struct BlossomConfig: Codable {
    var servers: [URL]           // e.g., ["https://blossom.primal.net"]
    var uploadServer: URL?       // Primary upload target
    var redundantUploads: Bool   // Upload to multiple servers
}
```

### Files to Modify

#### 3. `MyTube/Services/Storage/StorageConfigurationStore.swift`
**Changes:**
- Add `.blossom` case to `StorageModeSelection` enum
- Add `saveBlossomConfig()` and `loadBlossomConfig()` methods
- Store server list in Keychain

```swift
enum StorageModeSelection: String, Codable {
    case managed
    case byo
    case blossom  // NEW
}
```

#### 4. `MyTube/Services/Storage/StorageRouter.swift`
**Changes:**
- No changes needed (already supports any `MediaStorageClient`)

#### 5. `MyTube/AppEnvironment.swift`
**Changes:**
- Add logic to instantiate `BlossomClient` when mode is `.blossom`
- Wire up Blossom config to router

#### 6. `MyTube/Services/Storage/MediaStorageClient.swift`
**Changes (optional):**
- Add `deleteObject(key:)` method for Blossom cleanup
- Add `objectHash` to `StorageUploadResult` for Blossom verification

```swift
struct StorageUploadResult: Sendable {
    let key: String
    let accessURL: URL?
    let blobHash: Data?  // NEW: SHA256 hash for Blossom
}
```

---

## Phase 2: Update Video Share Flow

### Files to Modify

#### 7. `MyTube/Services/VideoSharePublisher.swift`
**Changes:**
- Store blob SHA256 hash in `VideoShareMessage`
- Use hash-based URL format for Blossom: `https://server/hash`
- Update key format from path-based to hash-based

**Before:**
```swift
let blob = VideoShareMessage.Blob(
    url: videoObjectURL.absoluteString,  // presigned URL
    key: encryptedResult.key              // path: videos/npub/uuid/media.bin
)
```

**After:**
```swift
let blob = VideoShareMessage.Blob(
    url: "https://blossom.example.com/\(encryptedResult.blobHash!.hexString)",
    key: encryptedResult.blobHash!.hexString  // SHA256 hash
)
```

#### 8. `MyTube/Services/RemoteVideoDownloader.swift`
**Changes:**
- Download by hash instead of presigned URL
- Verify downloaded blob hash matches expected hash

#### 9. `MyTube/Domain/VideoShareMessage.swift`
**Changes (optional):**
- Add `blobHash` field to `Blob` struct for explicit hash storage
- Add protocol version field for migration

```swift
struct Blob: Codable, Sendable {
    let url: String
    let mime: String
    let length: Int
    let key: String
    let hash: String?  // NEW: SHA256 hex for Blossom verification
}
```

---

## Phase 3: Backend Changes (tubestr-backend)

### Option A: Remove Storage Entirely
The backend becomes auth/subscription-only. Remove S3 code.

### Option B: Backend as Blossom Proxy (recommended initially)
Keep backend for quota enforcement but proxy to Blossom.

### Files to Modify

#### 10. `tubestr-backend/src/s3.ts` → `blossom.ts`
**Replace or rename:**
- Remove AWS SDK imports
- Add Blossom HTTP client
- Implement upload/download by hash

#### 11. `tubestr-backend/src/server.ts`
**Changes:**
- Replace `/presign/upload` with `/blossom/upload` (or keep same endpoint)
- Add `/blossom/servers` endpoint to return recommended servers
- Update quota tracking to use blob hashes

**New endpoints:**
```
POST /blossom/upload    - Upload blob (proxied to Blossom)
GET  /blossom/servers   - Return list of trusted Blossom servers
DELETE /blossom/:hash   - Delete blob (with NIP-98 auth)
```

#### 12. `tubestr-backend/prisma/schema.prisma`
**Changes:**
- Update `Upload` model to store blob hash instead of S3 key

```prisma
model Upload {
  id          String   @id @default(uuid())
  npub        String
  blobHash    String   @unique  // Changed from 'key'
  size        Int
  contentType String
  status      String   @default("pending")
  createdAt   DateTime @default(now())

  user        User     @relation(fields: [npub], references: [npub])
}
```

---

## Phase 4: Settings UI

### Files to Create/Modify

#### 13. `MyTube/Features/ParentZone/StorageSettingsView.swift` (if exists, modify)
**Changes:**
- Add Blossom server configuration UI
- Server URL input
- Test connection button
- Show current storage mode

---

## Phase 5: Migration Path for Existing Data

### Strategy
1. Keep MinIO data accessible during transition
2. New uploads go to Blossom
3. Existing videos remain accessible via old URLs
4. Optional: background migration job to copy to Blossom

### Files to Modify

#### 14. `MyTube/Services/RemoteVideoDownloader.swift`
**Changes:**
- Support both URL formats (presigned S3 and Blossom hash)
- Detect format from URL pattern

```swift
func download(videoId: UUID) async throws {
    let url = remoteVideo.blobURL
    if url.contains("blossom") || isHashBasedURL(url) {
        // Blossom download path
    } else {
        // Legacy S3 presigned URL path
    }
}
```

---

## File Change Summary

### iOS App (MyTube)

| File | Action | Priority |
|------|--------|----------|
| `Services/Storage/BlossomClient.swift` | **CREATE** | P0 |
| `Services/Storage/BlossomConfig.swift` | **CREATE** | P0 |
| `Services/Storage/StorageConfigurationStore.swift` | MODIFY | P0 |
| `Services/Storage/MediaStorageClient.swift` | MODIFY | P1 |
| `Services/VideoSharePublisher.swift` | MODIFY | P0 |
| `Services/RemoteVideoDownloader.swift` | MODIFY | P1 |
| `Domain/VideoShareMessage.swift` | MODIFY | P1 |
| `AppEnvironment.swift` | MODIFY | P0 |
| `Features/ParentZone/StorageSettingsView.swift` | CREATE/MODIFY | P2 |

### Backend (tubestr-backend)

| File | Action | Priority |
|------|--------|----------|
| `src/blossom.ts` | **CREATE** | P0 |
| `src/s3.ts` | DEPRECATE | P1 |
| `src/server.ts` | MODIFY | P0 |
| `prisma/schema.prisma` | MODIFY | P1 |
| `.env.example` | MODIFY | P2 |

### MDK (optional, for MIP-04 adoption)

| File | Action | Priority |
|------|--------|----------|
| `crates/mdk-ffi/src/lib.rs` | MODIFY | P2 |
| Swift bindings | GENERATE | P2 |

---

## Blossom Protocol Reference

### Upload Flow (BUD-01)
```
PUT /<sha256-hash>
Authorization: Nostr <base64-nip98-event>
Content-Type: application/octet-stream

<binary data>
```

### Download Flow
```
GET /<sha256-hash>
```

### Delete Flow (BUD-02)
```
DELETE /<sha256-hash>
Authorization: Nostr <base64-nip98-event>
```

### List Blobs (BUD-03)
```
GET /list/<pubkey>
Authorization: Nostr <base64-nip98-event>
```

---

## Testing Plan

1. **Unit tests for BlossomClient**
   - Upload/download roundtrip
   - Hash verification
   - NIP-98 auth generation

2. **Integration tests**
   - Upload to real Blossom server (testnet)
   - Download and verify hash
   - Delete with keypair

3. **Migration tests**
   - Existing S3 videos remain accessible
   - New videos upload to Blossom
   - Mixed-mode operation

---

## Rollout Strategy

1. **Alpha**: Blossom behind feature flag, internal testing only
2. **Beta**: Opt-in for power users via settings
3. **GA**: Default for new installs, migration for existing users
4. **Sunset**: Deprecate MinIO, remove backend storage code

---

## Resolved Questions

| Question | Decision |
|----------|----------|
| Blossom server | Self-hosted at `blossom.tubestr.app` |
| Quota enforcement | Keep backend for quotas + IAP |
| Thumbnail encryption | No - keep unencrypted |

## Open Questions

1. **Large file support?**
   - Blossom chunked uploads?
   - Current videos are typically <100MB

2. **Redundancy?**
   - Upload to backup servers?
   - Or single server sufficient?

---

## References

- [Blossom Protocol Spec](https://github.com/hzrd149/blossom)
- [BUD-01: Upload](https://github.com/hzrd149/blossom/blob/master/buds/01.md)
- [BUD-02: Delete](https://github.com/hzrd149/blossom/blob/master/buds/02.md)
- [NIP-98: HTTP Auth](https://github.com/nostr-protocol/nips/blob/master/98.md)
- MDK MIP-01: `mdk/crates/mdk-core/src/extension/group_image.rs`
- MDK MIP-04: `mdk/crates/mdk-core/src/encrypted_media/`
