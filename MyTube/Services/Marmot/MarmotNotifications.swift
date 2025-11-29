//
//  MarmotNotifications.swift
//  MyTube
//
//  Created by Codex on 02/20/26.
//

import Foundation

extension Notification.Name {
    static let marmotPendingWelcomesDidChange = Notification.Name("MarmotPendingWelcomesDidChange")
    static let marmotStateDidChange = Notification.Name("MarmotStateDidChange")
    static let marmotMessagesDidChange = Notification.Name("MarmotMessagesDidChange")
    /// Posted when a remote child key is discovered (e.g., from video shares or likes).
    /// userInfo contains "childKey" (String) - the canonical public key hex.
    static let remoteChildKeyDiscovered = Notification.Name("RemoteChildKeyDiscovered")
}
