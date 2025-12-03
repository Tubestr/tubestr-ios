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

    /// Posted when a new video share is projected to the local store.
    /// userInfo contains: "videoId" (String) - the remote video ID.
    static let remoteVideoShareProjected = Notification.Name("RemoteVideoShareProjected")

    // MARK: - Trust & Safety Notifications

    /// Posted when an incoming report is received.
    /// userInfo contains: "reportId" (String), "level" (Int), "videoId" (String), "mlsGroupId" (String)
    static let incomingReportReceived = Notification.Name("IncomingReportReceived")

    /// Posted when a moderator warning is received.
    /// userInfo contains: "reason" (String), "reportId" (String)
    static let moderatorWarningReceived = Notification.Name("ModeratorWarningReceived")

    /// Posted when an account-level action is received from moderators.
    /// userInfo contains: "action" (String), "reason" (String)
    static let accountActionReceived = Notification.Name("AccountActionReceived")
}
