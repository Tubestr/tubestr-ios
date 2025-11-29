//
//  PublishProgressOverlay.swift
//  MyTube
//
//  Shared progress overlay for video publishing (used by Editor and Capture).
//

import SwiftUI

/// Progress steps for video publishing workflow
enum PublishStep: String, CaseIterable {
    case preparing = "Getting ready..."
    case processing = "Processing video..."
    case scanning = "Safety check..."
    case saving = "Almost done..."
    case complete = "Done!"

    /// Kid-friendly icon for each step
    var iconName: String {
        switch self {
        case .preparing: return "gearshape"
        case .processing: return "film"
        case .scanning: return "checkmark.shield"
        case .saving: return "arrow.down.doc"
        case .complete: return "checkmark.circle.fill"
        }
    }
}

/// A reusable overlay showing publish progress with step indicators and celebration.
struct PublishProgressOverlay: View {
    let currentStep: PublishStep
    let accentColor: Color
    let showConfetti: Bool

    init(currentStep: PublishStep, accentColor: Color, showConfetti: Bool = true) {
        self.currentStep = currentStep
        self.accentColor = accentColor
        self.showConfetti = showConfetti
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()

            VStack(spacing: 24) {
                // Step dots showing progress
                HStack(spacing: 16) {
                    ForEach(Array(PublishStep.allCases.dropLast()), id: \.self) { step in
                        Circle()
                            .fill(stepReached(step) ? accentColor : Color.white.opacity(0.3))
                            .frame(width: 14, height: 14)
                            .overlay(
                                stepReached(step) ?
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(.white) : nil
                            )
                            .animation(.spring(response: 0.3), value: currentStep)
                    }
                }

                // Current step text with icon
                HStack(spacing: 12) {
                    Image(systemName: currentStep.iconName)
                        .font(.title2)
                    Text(currentStep.rawValue)
                        .font(.title3.bold())
                }
                .foregroundStyle(.white)
                .animation(.easeInOut, value: currentStep)

                if currentStep != .complete {
                    ProgressView()
                        .tint(accentColor)
                        .scaleEffect(1.2)
                } else {
                    // Celebration on complete
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(40)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )

            // Confetti on complete
            if showConfetti && currentStep == .complete {
                ConfettiView()
                    .frame(width: 400, height: 500)
                    .allowsHitTesting(false)
            }
        }
        .transition(.opacity)
    }

    private func stepReached(_ step: PublishStep) -> Bool {
        let allSteps = PublishStep.allCases
        guard let currentIndex = allSteps.firstIndex(of: currentStep),
              let stepIndex = allSteps.firstIndex(of: step) else { return false }
        return stepIndex <= currentIndex
    }
}

#Preview {
    PublishProgressOverlay(
        currentStep: .scanning,
        accentColor: .blue
    )
}

