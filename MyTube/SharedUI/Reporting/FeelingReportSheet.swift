//
//  FeelingReportSheet.swift
//  MyTube
//
//  A child-friendly, visual reporting flow that maps emotions to escalation levels.
//  Uses large icons and minimal text to be accessible for pre-readers.
//

import SwiftUI

// MARK: - Feeling Options

/// Represents how a child feels about a video, mapped to report escalation levels
enum ReportFeeling: String, CaseIterable, Identifiable {
    case uncomfortable   // Level 1: "This feels weird" - peer feedback
    case sad            // Level 1: "This makes me sad" - peer feedback
    case confused       // Level 2: "I don't understand" - ask parents
    case scared         // Level 2: "This scares me" - ask parents
    case angry          // Level 3: "This is really bad" - moderator

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .uncomfortable: return "😕"
        case .sad: return "😢"
        case .confused: return "🤔"
        case .scared: return "😨"
        case .angry: return "😠"
        }
    }

    var label: String {
        switch self {
        case .uncomfortable: return "Feels Weird"
        case .sad: return "Makes Me Sad"
        case .confused: return "Confusing"
        case .scared: return "Scary"
        case .angry: return "Really Bad"
        }
    }

    var color: Color {
        switch self {
        case .uncomfortable: return .orange
        case .sad: return .blue
        case .confused: return .purple
        case .scared: return .indigo
        case .angry: return .red
        }
    }

    /// Maps feeling to escalation level
    var level: ReportLevel {
        switch self {
        case .uncomfortable, .sad:
            return .peer
        case .confused, .scared:
            return .parent
        case .angry:
            return .moderator
        }
    }

    /// Maps feeling to a report reason
    var reason: ReportReason {
        switch self {
        case .uncomfortable, .confused:
            return .inappropriate
        case .sad:
            return .harassment
        case .scared:
            return .illegal
        case .angry:
            return .illegal
        }
    }
}

// MARK: - Feeling Report Sheet

struct FeelingReportSheet: View {
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var step: ReportStep = .feeling
    @State private var selectedFeeling: ReportFeeling?
    @State private var selectedAction: ReportAction = .reportOnly

    let isSubmitting: Bool
    @Binding var errorMessage: String?
    let childName: String?
    let allowsRelationshipActions: Bool
    let onSubmit: (ReportFeeling, ReportAction) -> Void
    let onCancel: () -> Void

    private var palette: KidPalette {
        appEnvironment.activeProfile.theme.kidPalette
    }

    enum ReportStep {
        case feeling
        case action
        case confirm
    }

    /// Returns a theme-aware color for a feeling
    private func feelingColor(_ feeling: ReportFeeling) -> Color {
        switch feeling {
        case .uncomfortable: return palette.warning
        case .sad: return palette.accent
        case .confused: return palette.accentSecondary
        case .scared: return palette.accent.opacity(0.8)
        case .angry: return palette.error
        }
    }

    var body: some View {
        ZStack {
            // Warm gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.15, green: 0.12, blue: 0.22),
                    Color(red: 0.10, green: 0.08, blue: 0.15)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                header

                // Content based on step
                Group {
                    switch step {
                    case .feeling:
                        feelingSelectionView
                    case .action:
                        actionSelectionView
                    case .confirm:
                        confirmationView
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }
        }
        .interactiveDismissDisabled(isSubmitting)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                if step == .feeling {
                    onCancel()
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.35)) {
                        step = step == .confirm ? .action : .feeling
                    }
                }
            } label: {
                Image(systemName: step == .feeling ? "xmark" : "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(.white.opacity(0.1)))
            }
            .disabled(isSubmitting)

            Spacer()

            // Progress dots
            HStack(spacing: 8) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(stepIndex >= index ? Color.white : Color.white.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }

            Spacer()

            // Spacer for symmetry
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var stepIndex: Int {
        switch step {
        case .feeling: return 0
        case .action: return 1
        case .confirm: return 2
        }
    }

    // MARK: - Step 1: Feeling Selection

    private var feelingSelectionView: some View {
        VStack(spacing: 32) {
            // Question with friendly illustration
            VStack(spacing: 16) {
                // Large question emoji
                Text("🎬")
                    .font(.system(size: 64))

                Text("How does this video make you feel?")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .padding(.top, 20)

            // Feeling options grid
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16)
            ], spacing: 16) {
                ForEach(ReportFeeling.allCases) { feeling in
                    FeelingButton(
                        feeling: feeling,
                        color: feelingColor(feeling),
                        isSelected: selectedFeeling == feeling
                    ) {
                        withAnimation(.spring(response: 0.3)) {
                            selectedFeeling = feeling
                        }
                        // Auto-advance after brief delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation(.spring(response: 0.35)) {
                                step = .action
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    // MARK: - Step 2: Action Selection

    private var actionSelectionView: some View {
        VStack(spacing: 32) {
            // Show selected feeling
            if let feeling = selectedFeeling {
                VStack(spacing: 12) {
                    Text(feeling.emoji)
                        .font(.system(size: 56))

                    Text("You feel: \(feeling.label)")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(.top, 20)
            }

            // What should we do?
            VStack(spacing: 16) {
                Text("What should we do?")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                // Level-based suggestion
                if let feeling = selectedFeeling {
                    Text(levelSuggestion(for: feeling.level))
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }

            // Action options
            VStack(spacing: 12) {
                ActionOptionButton(
                    icon: "hand.raised",
                    title: "Just Tell Them",
                    subtitle: "Let them know how you feel",
                    color: palette.accent,
                    isSelected: selectedAction == .reportOnly
                ) {
                    selectedAction = .reportOnly
                }

                if allowsRelationshipActions {
                    ActionOptionButton(
                        icon: "eye.slash",
                        title: "Hide Their Videos",
                        subtitle: "Stop seeing videos from them",
                        color: palette.warning,
                        isSelected: selectedAction == .unfollow
                    ) {
                        selectedAction = .unfollow
                    }

                    ActionOptionButton(
                        icon: "xmark.shield",
                        title: "Block Them",
                        subtitle: "They can't send videos anymore",
                        color: palette.error,
                        isSelected: selectedAction == .block
                    ) {
                        selectedAction = .block
                    }
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            // Next button
            Button {
                withAnimation(.spring(response: 0.35)) {
                    step = .confirm
                }
            } label: {
                HStack(spacing: 12) {
                    Text("Next")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(selectedFeeling.map { feelingColor($0) } ?? palette.accent)
                )
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Step 3: Confirmation

    private var confirmationView: some View {
        VStack(spacing: 24) {
            // Summary
            if let feeling = selectedFeeling {
                VStack(spacing: 20) {
                    // Big emoji
                    Text(feeling.emoji)
                        .font(.system(size: 72))
                        .padding(.top, 20)

                    // Summary text
                    VStack(spacing: 8) {
                        Text("Ready to send?")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text(confirmationMessage(feeling: feeling, action: selectedAction))
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }

                    // Visual indication of who receives
                    RecipientIndicator(
                        level: feeling.level,
                        peerColor: palette.accent,
                        parentColor: palette.warning,
                        moderatorColor: palette.error
                    )
                    .padding(.horizontal, 24)
                }
            }

            Spacer()

            // Error message
            if let error = errorMessage, !error.isEmpty {
                Text(error)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.error)
                    .padding(.horizontal, 24)
            }

            // Submit button
            Button {
                guard let feeling = selectedFeeling else { return }
                onSubmit(feeling, selectedAction)
            } label: {
                HStack(spacing: 12) {
                    if isSubmitting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 18, weight: .semibold))
                        Text("Send")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    selectedFeeling.map { feelingColor($0) } ?? palette.accent,
                                    (selectedFeeling.map { feelingColor($0) } ?? palette.accent).opacity(0.8)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                .shadow(color: (selectedFeeling.map { feelingColor($0) } ?? palette.accent).opacity(0.4), radius: 16, y: 8)
            }
            .disabled(isSubmitting)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Helpers

    private func levelSuggestion(for level: ReportLevel) -> String {
        switch level {
        case .peer:
            return "We'll let them know how you feel so they can do better"
        case .parent:
            return "We'll ask both parents to help figure this out together"
        case .moderator:
            return "We'll tell the Tubestr safety team about this"
        }
    }

    private func confirmationMessage(feeling: ReportFeeling, action: ReportAction) -> String {
        var base: String
        switch feeling.level {
        case .peer:
            base = "We'll tell them this made you feel \(feeling.label.lowercased())."
        case .parent:
            base = "Both parents will be asked to help."
        case .moderator:
            base = "The Tubestr team will look at this."
        }

        switch action {
        case .unfollow:
            base += " You won't see their videos anymore."
        case .block:
            base += " They won't be able to send you videos."
        default:
            break
        }

        return base
    }
}

// MARK: - Feeling Button

private struct FeelingButton: View {
    let feeling: ReportFeeling
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                // Large emoji
                Text(feeling.emoji)
                    .font(.system(size: 48))

                // Label
                Text(feeling.label)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isSelected ? color.opacity(0.3) : .white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(isSelected ? color : .clear, lineWidth: 3)
                    )
            )
            .scaleEffect(isSelected ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(feeling.label)
    }
}

// MARK: - Action Option Button

private struct ActionOptionButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(isSelected ? color : color.opacity(0.2))
                        .frame(width: 48, height: 48)

                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : color)
                }

                // Text
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }

                Spacer()

                // Checkmark
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(color)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? color.opacity(0.15) : .white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(isSelected ? color.opacity(0.5) : .white.opacity(0.1), lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Recipient Indicator

private struct RecipientIndicator: View {
    let level: ReportLevel
    let peerColor: Color
    let parentColor: Color
    let moderatorColor: Color

    var body: some View {
        HStack(spacing: 16) {
            ForEach(0..<3) { index in
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(isActive(index) ? levelColor : .white.opacity(0.1))
                            .frame(width: 56, height: 56)

                        Image(systemName: iconForIndex(index))
                            .font(.system(size: 24))
                            .foregroundStyle(isActive(index) ? .white : .white.opacity(0.4))
                    }

                    Text(labelForIndex(index))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(isActive(index) ? .white : .white.opacity(0.4))
                }
                .frame(maxWidth: .infinity)

                if index < 2 {
                    // Connector line
                    Rectangle()
                        .fill(isActive(index + 1) ? levelColor.opacity(0.5) : .white.opacity(0.1))
                        .frame(height: 2)
                        .frame(maxWidth: 32)
                        .offset(y: -16)
                }
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(0.05))
        )
    }

    private func isActive(_ index: Int) -> Bool {
        switch level {
        case .peer: return index == 0
        case .parent: return index <= 1
        case .moderator: return true
        }
    }

    private var levelColor: Color {
        switch level {
        case .peer: return peerColor
        case .parent: return parentColor
        case .moderator: return moderatorColor
        }
    }

    private func iconForIndex(_ index: Int) -> String {
        switch index {
        case 0: return "person.2"
        case 1: return "figure.2.and.child.holdinghands"
        case 2: return "shield.checkered"
        default: return "questionmark"
        }
    }

    private func labelForIndex(_ index: Int) -> String {
        switch index {
        case 0: return "Them"
        case 1: return "Parents"
        case 2: return "Tubestr"
        default: return ""
        }
    }
}

// MARK: - Preview

#Preview {
    FeelingReportSheet(
        isSubmitting: false,
        errorMessage: .constant(nil),
        childName: "Emma",
        allowsRelationshipActions: true,
        onSubmit: { feeling, action in
            print("Submitted: \(feeling.label) with action \(action)")
        },
        onCancel: {}
    )
}
