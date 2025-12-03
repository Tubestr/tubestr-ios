//
//  ConversationCardsView.swift
//  MyTube
//
//  A warm, conversation-focused way to display reports between families.
//  Designed to prompt parent-child conversations, not punishments.
//

import SwiftUI

// MARK: - Conversation Cards Container

/// Displays reports as conversation starters, grouped by level
struct ConversationCardsView: View {
    @EnvironmentObject private var appEnvironment: AppEnvironment
    let inboundReports: [ReportModel]
    let outboundReports: [ReportModel]
    let onMarkRead: (ReportModel) -> Void
    let onStartConversation: (ReportModel) -> Void

    private var palette: KidPalette {
        appEnvironment.activeProfile.theme.kidPalette
    }

    var body: some View {
        VStack(spacing: 24) {
            // Header with gentle framing
            headerSection

            // Needs conversation (Level 2+ or unread)
            if !needsConversation.isEmpty {
                needsConversationSection
            }

            // Recent feedback (Level 1, already read)
            if !recentFeedback.isEmpty {
                recentFeedbackSection
            }

            // Your reports to others
            if !outboundReports.isEmpty {
                yourReportsSection
            }

            // Empty state
            if inboundReports.isEmpty && outboundReports.isEmpty {
                emptyState
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Computed Properties

    private var needsConversation: [ReportModel] {
        inboundReports.filter { report in
            report.level.rawValue >= 2 || report.status == .pending
        }.sorted { $0.createdAt > $1.createdAt }
    }

    private var recentFeedback: [ReportModel] {
        inboundReports.filter { report in
            report.level == .peer && report.status != .pending
        }.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 32))
                .foregroundStyle(palette.accent.opacity(0.8))

            Text("Family Conversations")
                .font(.system(size: 20, weight: .semibold, design: .rounded))

            Text("When kids share how they feel, it's a chance to talk and learn together")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(.vertical, 16)
    }

    // MARK: - Needs Conversation Section

    private var needsConversationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("Let's Talk")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            } icon: {
                Image(systemName: "heart.circle.fill")
                    .foregroundStyle(palette.warning)
            }
            .padding(.horizontal, 16)

            ForEach(needsConversation, id: \.id) { report in
                ConversationCard(
                    report: report,
                    style: .needsAttention,
                    onMarkRead: { onMarkRead(report) },
                    onStartConversation: { onStartConversation(report) }
                )
            }
        }
    }

    // MARK: - Recent Feedback Section

    private var recentFeedbackSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("Recent Feedback")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(palette.success)
            }
            .padding(.horizontal, 16)

            ForEach(recentFeedback, id: \.id) { report in
                ConversationCard(
                    report: report,
                    style: .resolved,
                    onMarkRead: { onMarkRead(report) },
                    onStartConversation: { onStartConversation(report) }
                )
            }
        }
    }

    // MARK: - Your Reports Section

    private var yourReportsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("Feedback You Shared")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            } icon: {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundStyle(palette.accent)
            }
            .padding(.horizontal, 16)

            ForEach(outboundReports, id: \.id) { report in
                OutboundReportCard(report: report)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundStyle(palette.success.opacity(0.6))

            Text("All good here!")
                .font(.system(size: 17, weight: .semibold, design: .rounded))

            Text("No conversations needed right now.\nEveryone's having a great time!")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Conversation Card

struct ConversationCard: View {
    @EnvironmentObject private var appEnvironment: AppEnvironment
    let report: ReportModel
    let style: CardStyle
    let onMarkRead: () -> Void
    let onStartConversation: () -> Void

    private var palette: KidPalette {
        appEnvironment.activeProfile.theme.kidPalette
    }

    enum CardStyle {
        case needsAttention
        case resolved
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Top row: feeling + time
            HStack(alignment: .top) {
                // Feeling indicator
                feelingBadge

                Spacer()

                // Time
                Text(report.createdAt, style: .relative)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            // What happened
            VStack(alignment: .leading, spacing: 8) {
                Text(conversationPrompt)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)

                // Level indicator with friendly explanation
                levelExplanation
            }

            // Conversation starters (only for needs attention)
            if style == .needsAttention {
                conversationStarters
            }

            // Action buttons
            HStack(spacing: 12) {
                if style == .needsAttention {
                    Button {
                        onStartConversation()
                    } label: {
                        Label("We Talked", systemImage: "checkmark.bubble")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(levelColor)
                }

                if report.status == .pending {
                    Button {
                        onMarkRead()
                    } label: {
                        Text("Mark as Read")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(cardBorder, lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
    }

    // MARK: - Feeling Badge

    private var feelingBadge: some View {
        HStack(spacing: 8) {
            Text(feelingEmoji)
                .font(.system(size: 24))

            VStack(alignment: .leading, spacing: 2) {
                Text(feelingLabel)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text("from another family")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(levelColor.opacity(0.15))
        )
    }

    // MARK: - Level Explanation

    private var levelExplanation: some View {
        HStack(spacing: 6) {
            Image(systemName: levelIcon)
                .font(.system(size: 12))
            Text(levelText)
                .font(.system(size: 12, weight: .medium, design: .rounded))
        }
        .foregroundStyle(levelColor)
    }

    // MARK: - Conversation Starters

    private var conversationStarters: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Try asking:")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            ForEach(conversationQuestions, id: \.self) { question in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(.top, 3)

                    Text(question)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.8))
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
    }

    // MARK: - Computed Properties

    private var feelingEmoji: String {
        // Try to extract feeling from note, otherwise use reason
        if let note = report.note?.lowercased() {
            if note.contains("weird") { return "😕" }
            if note.contains("sad") { return "😢" }
            if note.contains("confus") { return "🤔" }
            if note.contains("scar") { return "😨" }
            if note.contains("bad") || note.contains("angry") { return "😠" }
        }

        switch report.reason {
        case .harassment: return "😢"
        case .inappropriate: return "😕"
        case .illegal: return "😨"
        case .spam: return "🙄"
        case .other: return "🤔"
        }
    }

    private var feelingLabel: String {
        if let note = report.note?.lowercased() {
            if note.contains("weird") { return "Felt weird" }
            if note.contains("sad") { return "Felt sad" }
            if note.contains("confus") { return "Was confused" }
            if note.contains("scar") { return "Felt scared" }
            if note.contains("bad") || note.contains("angry") { return "Upset" }
        }

        switch report.reason {
        case .harassment: return "Felt hurt"
        case .inappropriate: return "Uncomfortable"
        case .illegal: return "Concerned"
        case .spam: return "Annoyed"
        case .other: return "Had a concern"
        }
    }

    private var conversationPrompt: String {
        switch report.level {
        case .peer:
            return "A child in another family shared how they felt about a video."
        case .parent:
            return "Another family wants to talk about something that happened."
        case .moderator:
            return "Something serious was shared with Tubestr's safety team."
        }
    }

    private var levelIcon: String {
        switch report.level {
        case .peer: return "person.2"
        case .parent: return "figure.2.and.child.holdinghands"
        case .moderator: return "shield.checkered"
        }
    }

    private var levelText: String {
        switch report.level {
        case .peer: return "Shared with your family"
        case .parent: return "Both families asked to talk"
        case .moderator: return "Safety team notified"
        }
    }

    private var levelColor: Color {
        switch report.level {
        case .peer: return palette.accent
        case .parent: return palette.warning
        case .moderator: return palette.error
        }
    }

    private var cardBackground: Color {
        switch style {
        case .needsAttention:
            return levelColor.opacity(0.05)
        case .resolved:
            return Color.primary.opacity(0.02)
        }
    }

    private var cardBorder: Color {
        switch style {
        case .needsAttention:
            return levelColor.opacity(0.2)
        case .resolved:
            return Color.primary.opacity(0.08)
        }
    }

    private var conversationQuestions: [String] {
        switch report.level {
        case .peer:
            return [
                "What do you think made them feel that way?",
                "How would you feel if you got that video?"
            ]
        case .parent:
            return [
                "Tell me about this video you shared",
                "How do you think the other kid felt?",
                "What could we do differently next time?"
            ]
        case .moderator:
            return [
                "Can you tell me what happened?",
                "I'm not upset, I just want to understand",
                "Let's figure this out together"
            ]
        }
    }
}

// MARK: - Outbound Report Card

struct OutboundReportCard: View {
    @EnvironmentObject private var appEnvironment: AppEnvironment
    let report: ReportModel

    private var palette: KidPalette {
        appEnvironment.activeProfile.theme.kidPalette
    }

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(statusText)
                    .font(.system(size: 14, weight: .medium, design: .rounded))

                Text(report.createdAt, style: .relative)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Level badge
            Text(report.level.displayName)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(levelColor.opacity(0.15))
                )
                .foregroundStyle(levelColor)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
    }

    private var statusColor: Color {
        switch report.status {
        case .pending: return palette.warning
        case .acknowledged: return palette.accent
        case .actioned: return palette.success
        case .dismissed: return .gray
        }
    }

    private var statusText: String {
        switch report.status {
        case .pending: return "Feedback sent, waiting for response"
        case .acknowledged: return "The other family saw your feedback"
        case .actioned: return "The other family took action"
        case .dismissed: return "Feedback was reviewed"
        }
    }

    private var levelColor: Color {
        switch report.level {
        case .peer: return palette.accent
        case .parent: return palette.warning
        case .moderator: return palette.error
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        ConversationCardsView(
            inboundReports: [
                ReportModel(
                    id: UUID(),
                    videoId: "video1",
                    subjectChild: "child1",
                    reporterKey: "npub1reporter",
                    reason: .inappropriate,
                    note: "Child reported feeling: Feels Weird",
                    createdAt: Date().addingTimeInterval(-3600),
                    status: .pending,
                    actionTaken: nil,
                    lastActionAt: nil,
                    isOutbound: false,
                    deliveredAt: Date(),
                    level: .parent,
                    reporterChild: "otherchild",
                    recipientType: "parents"
                )
            ],
            outboundReports: [
                ReportModel(
                    id: UUID(),
                    videoId: "video2",
                    subjectChild: "child2",
                    reporterKey: "npub1me",
                    reason: .harassment,
                    note: "Child reported feeling: Makes Me Sad",
                    createdAt: Date().addingTimeInterval(-7200),
                    status: .acknowledged,
                    actionTaken: .reportOnly,
                    lastActionAt: nil,
                    isOutbound: true,
                    deliveredAt: Date(),
                    level: .peer,
                    reporterChild: "mychild",
                    recipientType: "group"
                )
            ],
            onMarkRead: { _ in },
            onStartConversation: { _ in }
        )
    }
}
