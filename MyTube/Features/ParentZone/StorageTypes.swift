//
//  StorageTypes.swift
//  MyTube
//
//  Storage-related types extracted from ParentZoneViewModel for organization.
//

import Foundation

struct CloudEntitlement: Equatable {
    let plan: String
    let status: String
    let expiresAt: Date?
    let quotaBytes: Int64?
    let usedBytes: Int64?

    init(response: EntitlementResponse) {
        self.plan = response.plan
        self.status = response.status
        self.expiresAt = response.expiresAt
        self.quotaBytes = CloudEntitlement.parseBytes(response.quotaBytes)
        self.usedBytes = CloudEntitlement.parseBytes(response.usedBytes)
    }

    var statusLabel: String {
        status
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    var isActive: Bool {
        status.caseInsensitiveCompare("active") == .orderedSame
    }

    var usageSummary: String? {
        guard let quotaBytes else { return nil }
        let used = max(usedBytes ?? 0, 0)
        let quotaDescription = CloudEntitlement.byteFormatter.string(fromByteCount: quotaBytes)
        let usedDescription = CloudEntitlement.byteFormatter.string(fromByteCount: used)
        return "\(usedDescription) of \(quotaDescription) used"
    }

    var quotaDescription: String? {
        guard let quotaBytes else { return nil }
        return CloudEntitlement.byteFormatter.string(fromByteCount: quotaBytes)
    }

    var usageFraction: Double? {
        guard let quota = quotaBytes,
              quota > 0,
              let used = usedBytes else { return nil }
        return min(max(Double(used) / Double(quota), 0), 1)
    }

    private static func parseBytes(_ value: String?) -> Int64? {
        guard let value else { return nil }
        return Int64(value)
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()
}

struct StorageUsage: Equatable {
    let media: Int64
    let thumbs: Int64
    let edits: Int64

    static let empty = StorageUsage(media: 0, thumbs: 0, edits: 0)

    var total: Int64 { media + thumbs + edits }

    var formattedTotal: String {
        StorageUsage.byteFormatter.string(fromByteCount: total)
    }

    var formattedMedia: String {
        StorageUsage.byteFormatter.string(fromByteCount: media)
    }

    var formattedThumbs: String {
        StorageUsage.byteFormatter.string(fromByteCount: thumbs)
    }

    var formattedEdits: String {
        StorageUsage.byteFormatter.string(fromByteCount: edits)
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()
}
