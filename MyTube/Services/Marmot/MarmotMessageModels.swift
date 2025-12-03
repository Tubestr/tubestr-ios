//
//  MarmotMessageModels.swift
//  MyTube
//
//  Created by Assistant on 03/02/26.
//

import Foundation
import MDKBindings

typealias GroupUpdateResult = AddMembersResult

enum MarmotPayloadType: String, Codable, CaseIterable, Sendable {
    case videoShare = "mytube/video_share"
    case videoRevoke = "mytube/video_revoke"
    case videoDelete = "mytube/video_delete"
    case like = "mytube/like"
    case report = "mytube/report"
}

struct VideoShareMessage: Codable, Sendable {
    struct Meta: Codable, Sendable {
        let title: String?
        let duration: Double?
        let createdAt: Double?

        init(title: String?, duration: Double?, createdAt: Date?) {
            self.title = title
            self.duration = duration
            self.createdAt = createdAt?.timeIntervalSince1970
        }

        private enum CodingKeys: String, CodingKey {
            case title
            case duration = "dur"
            case createdAt = "created_at"
        }

        var createdAtDate: Date? {
            guard let createdAt else { return nil }
            return Date(timeIntervalSince1970: createdAt)
        }
    }

    struct Blob: Codable, Sendable {
        let url: String
        let mime: String
        let length: Int?
        let key: String?

        init(url: String, mime: String, length: Int?, key: String? = nil) {
            self.url = url
            self.mime = mime
            self.length = length
            self.key = key
        }

        private enum CodingKeys: String, CodingKey {
            case url
            case mime
            case length = "len"
            case key
        }
    }

    struct Crypto: Codable, Sendable {
        struct Wrap: Codable, Sendable {
            let ephemeralPub: String
            let wrapSalt: String
            let wrapNonce: String
            let keyWrapped: String

            init(ephemeralPub: String, wrapSalt: String, wrapNonce: String, keyWrapped: String) {
                self.ephemeralPub = ephemeralPub
                self.wrapSalt = wrapSalt
                self.wrapNonce = wrapNonce
                self.keyWrapped = keyWrapped
            }

            private enum CodingKeys: String, CodingKey {
                case ephemeralPub = "ephemeral_pub"
                case wrapSalt = "wrap_salt"
                case wrapNonce = "wrap_nonce"
                case keyWrapped = "key_wrapped"
            }
        }

        let algMedia: String
        let nonceMedia: String
        let mediaKey: String?
        let algWrap: String?
        let wrap: Wrap?

        init(
            algMedia: String,
            nonceMedia: String,
            mediaKey: String?,
            algWrap: String? = nil,
            wrap: Wrap? = nil
        ) {
            self.algMedia = algMedia
            self.nonceMedia = nonceMedia
            self.mediaKey = mediaKey
            self.algWrap = algWrap
            self.wrap = wrap
        }

        private enum CodingKeys: String, CodingKey {
            case algMedia = "alg_media"
            case nonceMedia = "nonce_media"
            case mediaKey = "media_key"
            case algWrap = "alg_wrap"
            case wrap
        }
    }

    struct Policy: Codable, Sendable {
        let visibility: String?
        let expiresAt: Double?
        let version: Int?

        init(visibility: String?, expiresAt: Date?, version: Int?) {
            self.visibility = visibility
            self.expiresAt = expiresAt?.timeIntervalSince1970
            self.version = version
        }

        private enum CodingKeys: String, CodingKey {
            case visibility
            case expiresAt = "expires_at"
            case version
        }

        var expiresAtDate: Date? {
            guard let expiresAt else { return nil }
            return Date(timeIntervalSince1970: expiresAt)
        }
    }

    let t: String
    let videoId: String
    let ownerChild: String  // Child's bech32 npub (e.g., "npub1...")
    let childName: String?  // Display name of the child
    let meta: Meta?
    let blob: Blob
    let thumb: Blob
    let crypto: Crypto
    let policy: Policy?
    let by: String  // Parent's pubkey who is sharing
    let ts: Double

    init(
        videoId: String,
        ownerChild: String,
        childName: String? = nil,
        meta: Meta?,
        blob: Blob,
        thumb: Blob,
        crypto: Crypto,
        policy: Policy?,
        by: String,
        timestamp: Date
    ) {
        self.t = MarmotPayloadType.videoShare.rawValue
        self.videoId = videoId
        self.ownerChild = ownerChild
        self.childName = childName
        self.meta = meta
        self.blob = blob
        self.thumb = thumb
        self.crypto = crypto
        self.policy = policy
        self.by = by
        self.ts = timestamp.timeIntervalSince1970
    }

    private enum CodingKeys: String, CodingKey {
        case t
        case videoId = "video_id"
        case ownerChild = "owner_child"
        case childName = "child_name"
        case meta
        case blob
        case thumb
        case crypto
        case policy
        case by
        case ts
    }
}

struct VideoLifecycleMessage: Codable, Sendable {
    let t: String
    let videoId: String
    let reason: String?
    let by: String
    let ts: Double

    init(kind: MarmotPayloadType, videoId: String, reason: String?, by: String, timestamp: Date) {
        precondition(kind == .videoRevoke || kind == .videoDelete, "Lifecycle message must be revoke/delete")
        self.t = kind.rawValue
        self.videoId = videoId
        self.reason = reason
        self.by = by
        self.ts = timestamp.timeIntervalSince1970
    }

    private enum CodingKeys: String, CodingKey {
        case t
        case videoId = "video_id"
        case reason
        case by
        case ts
    }
}

struct LikeMessage: Codable, Sendable {
    let t: String
    let videoId: String
    let viewerChild: String
    let by: String
    let ts: Double

    init(videoId: String, viewerChild: String, by: String, timestamp: Date) {
        self.t = MarmotPayloadType.like.rawValue
        self.videoId = videoId
        self.viewerChild = viewerChild
        self.by = by
        self.ts = timestamp.timeIntervalSince1970
    }

    private enum CodingKeys: String, CodingKey {
        case t
        case videoId = "video_id"
        case viewerChild = "viewer_child"
        case by
        case ts
    }
}

struct ReportMessage: Codable, Sendable {
    let t: String
    let videoId: String
    let subjectChild: String
    let reason: String
    let note: String?
    let by: String
    let ts: Double

    // New fields for 3-level reporting (optional for backward compatibility)
    let level: Int?                  // 1=peer, 2=parent, 3=moderator (default: 1)
    let recipientType: String?       // "group", "parents", "moderators"
    let reporterChild: String?       // Child profile UUID who initiated
    let reportId: String?            // UUID for tracking across systems

    /// Computed property for backward compatibility
    var resolvedLevel: Int { level ?? 1 }

    init(
        videoId: String,
        subjectChild: String,
        reason: String,
        note: String?,
        by: String,
        timestamp: Date,
        level: Int? = nil,
        recipientType: String? = nil,
        reporterChild: String? = nil,
        reportId: String? = nil
    ) {
        self.t = MarmotPayloadType.report.rawValue
        self.videoId = videoId
        self.subjectChild = subjectChild
        self.reason = reason
        self.note = note
        self.by = by
        self.ts = timestamp.timeIntervalSince1970
        self.level = level
        self.recipientType = recipientType
        self.reporterChild = reporterChild
        self.reportId = reportId
    }

    private enum CodingKeys: String, CodingKey {
        case t
        case videoId = "video_id"
        case subjectChild = "subject_child"
        case reason
        case note
        case by
        case ts
        case level
        case recipientType = "recipient_type"
        case reporterChild = "reporter_child"
        case reportId = "report_id"
    }
}

/// Message from Tubestr moderators in response to Level 3 reports
struct ModeratorActionMessage: Codable, Sendable {
    let t: String                    // "mytube/mod_action"
    let reportId: String             // Original report ID
    let videoId: String?             // Target video (if applicable)
    let subjectParentKey: String?    // Target parent (if applicable)
    let action: String               // Action taken
    let reason: String?              // Explanation
    let by: String                   // Moderator npub
    let ts: Double

    private enum CodingKeys: String, CodingKey {
        case t
        case reportId = "report_id"
        case videoId = "video_id"
        case subjectParentKey = "subject_parent_key"
        case action
        case reason
        case by
        case ts
    }
}

/// Actions moderators can take
enum ModeratorAction: String, Codable, Sendable {
    case dismiss = "dismiss"         // Report dismissed, no action
    case warn = "warn"               // Warning issued
    case removeContent = "remove"    // Content removed
    case suspendAccount = "suspend"  // Account suspended
    case banAccount = "ban"          // Account banned
}

extension Data {
    init?(hexString: String) {
        let cleaned = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count % 2 == 0 else { return nil }

        var data = Data(capacity: cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let nextIndex = cleaned.index(index, offsetBy: 2)
            guard nextIndex <= cleaned.endIndex else { return nil }
            let byteString = cleaned[index..<nextIndex]
            guard let byte = UInt8(byteString, radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        self = data
    }
}
