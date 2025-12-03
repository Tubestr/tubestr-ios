//
//  ModerationConfig.swift
//  MyTube
//
//  Created by Assistant on 12/03/25.
//

import Foundation

/// Configuration for moderation features
enum ModerationConfig {

    /// Relays that receive Level 3 moderation reports
    static let moderationRelays = ["wss://no.str.cr"]

    /// Known Tubestr moderator public keys
    /// These keys can issue moderator actions that clients will respect
    static var moderatorKeys: Set<String> = [
        // Add moderator npubs here
        // "npub1..."
    ]

    /// Check if a public key belongs to a moderator
    static func isModerator(_ pubkey: String) -> Bool {
        moderatorKeys.contains(pubkey)
    }

    /// Nostr kind for moderator action messages
    static let moderatorActionKind: UInt16 = 4550
}
