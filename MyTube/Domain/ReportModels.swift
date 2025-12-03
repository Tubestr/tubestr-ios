//
//  ReportModels.swift
//  MyTube
//
//  Created by Assistant on 02/15/26.
//

import CoreData
import Foundation

enum ReportReason: String, CaseIterable, Codable, Sendable {
    case harassment
    case spam
    case inappropriate
    case illegal
    case other

    var displayName: String {
        switch self {
        case .harassment:
            return "Harassment or bullying"
        case .spam:
            return "Spam or scams"
        case .inappropriate:
            return "Inappropriate for kids"
        case .illegal:
            return "Illegal or dangerous"
        case .other:
            return "Other"
        }
    }
}

/// The escalation level of a report
enum ReportLevel: Int, Codable, CaseIterable, Sendable {
    case peer = 1        // Direct feedback to the other family
    case parent = 2      // Escalate to both parents for guidance
    case moderator = 3   // Escalate to Tubestr safety team

    var displayName: String {
        switch self {
        case .peer: return "Tell Them"
        case .parent: return "Ask Parents"
        case .moderator: return "Report to Tubestr"
        }
    }

    var description: String {
        switch self {
        case .peer: return "Let them know this doesn't feel good"
        case .parent: return "Ask both parents to help figure this out"
        case .moderator: return "This is serious and needs Tubestr's help"
        }
    }

    var recipientType: String {
        switch self {
        case .peer: return "group"
        case .parent: return "parents"
        case .moderator: return "moderators"
        }
    }
}

enum ReportStatus: String, Codable, Sendable {
    case pending
    case acknowledged
    case dismissed
    case actioned
}

enum ReportAction: String, Codable, Sendable {
    case none
    case reportOnly
    case unfollow
    case block
    case deleted
    case conversationHad
}

struct ReportModel: Identifiable, Hashable, Sendable {
    let id: UUID
    let videoId: String
    let subjectChild: String
    let reporterKey: String
    let reason: ReportReason
    let note: String?
    let createdAt: Date
    let status: ReportStatus
    let actionTaken: ReportAction?
    let lastActionAt: Date?
    let isOutbound: Bool
    let deliveredAt: Date?
    let level: ReportLevel
    let reporterChild: String?
    let recipientType: String

    init(
        id: UUID,
        videoId: String,
        subjectChild: String,
        reporterKey: String,
        reason: ReportReason,
        note: String?,
        createdAt: Date,
        status: ReportStatus,
        actionTaken: ReportAction?,
        lastActionAt: Date?,
        isOutbound: Bool,
        deliveredAt: Date?,
        level: ReportLevel = .peer,
        reporterChild: String? = nil,
        recipientType: String = "group"
    ) {
        self.id = id
        self.videoId = videoId
        self.subjectChild = subjectChild
        self.reporterKey = reporterKey
        self.reason = reason
        self.note = note
        self.createdAt = createdAt
        self.status = status
        self.actionTaken = actionTaken
        self.lastActionAt = lastActionAt
        self.isOutbound = isOutbound
        self.deliveredAt = deliveredAt
        self.level = level
        self.reporterChild = reporterChild
        self.recipientType = recipientType
    }

    init?(entity: ReportEntity) {
        guard
            let id = entity.id,
            let videoId = entity.videoId,
            let subjectChild = entity.subjectChild,
            let reporterKey = entity.reporterKey,
            let reasonRaw = entity.reason,
            let createdAt = entity.createdAt,
            let statusRaw = entity.status
        else {
            return nil
        }

        guard let reason = ReportReason(rawValue: reasonRaw) else {
            return nil
        }
        let status = ReportStatus(rawValue: statusRaw) ?? .pending
        let actionTaken = entity.actionTaken.flatMap { ReportAction(rawValue: $0) }
        let level = ReportLevel(rawValue: Int(entity.level)) ?? .peer
        let recipientType = entity.recipientType ?? "group"

        self.init(
            id: id,
            videoId: videoId,
            subjectChild: subjectChild,
            reporterKey: reporterKey,
            reason: reason,
            note: entity.note,
            createdAt: createdAt,
            status: status,
            actionTaken: actionTaken,
            lastActionAt: entity.lastActionAt,
            isOutbound: entity.isOutbound,
            deliveredAt: entity.deliveredAt,
            level: level,
            reporterChild: entity.reporterChild,
            recipientType: recipientType
        )
    }

    var isResolved: Bool {
        status == .dismissed || status == .actioned
    }
}
