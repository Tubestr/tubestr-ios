//
//  NookDecorations.swift
//  MyTube
//
//  Cozy decorative elements for Nook's kid-friendly UI
//

import SwiftUI

// MARK: - Floating Decorations

/// Floating decorations that gently animate in the background based on theme
struct FloatingDecorations: View {
    @EnvironmentObject private var appEnvironment: AppEnvironment
    let intensity: DecorationIntensity

    enum DecorationIntensity {
        case subtle   // Barely visible
        case gentle   // Calm presence
        case lively   // More active

        var count: Int {
            switch self {
            case .subtle: return 6
            case .gentle: return 10
            case .lively: return 16
            }
        }

        var opacity: Double {
            switch self {
            case .subtle: return 0.15
            case .gentle: return 0.25
            case .lively: return 0.35
            }
        }
    }

    var body: some View {
        let theme = appEnvironment.activeProfile.theme
        GeometryReader { geo in
            ZStack {
                ForEach(0..<intensity.count, id: \.self) { index in
                    FloatingDecoration(
                        theme: theme,
                        index: index,
                        containerSize: geo.size,
                        intensity: intensity
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct FloatingDecoration: View {
    let theme: ThemeDescriptor
    let index: Int
    let containerSize: CGSize
    @State private var offset: CGSize = .zero
    @State private var rotation: Double = 0
    @State private var scale: CGFloat = 1.0
    let intensity: FloatingDecorations.DecorationIntensity

    private var basePosition: CGPoint {
        // Deterministic positions based on index
        let seed = Double(index * 137 + 42)
        let x = (sin(seed) * 0.5 + 0.5) * containerSize.width
        let y = (cos(seed * 1.3) * 0.5 + 0.5) * containerSize.height
        return CGPoint(x: x, y: y)
    }

    private var decorationSize: CGFloat {
        let base: CGFloat = 16 + CGFloat(index % 4) * 12
        return base
    }

    var body: some View {
        decorationShape
            .position(x: basePosition.x + offset.width, y: basePosition.y + offset.height)
            .rotationEffect(.degrees(rotation))
            .scaleEffect(scale)
            .onAppear {
                startAnimation()
            }
    }

    @ViewBuilder
    private var decorationShape: some View {
        let palette = theme.kidPalette

        switch theme {
        case .campfire:
            // Warm ember/spark shapes
            if index % 3 == 0 {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [palette.accent.opacity(intensity.opacity), palette.accentSecondary.opacity(intensity.opacity * 0.5)],
                            center: .center,
                            startRadius: 0,
                            endRadius: decorationSize / 2
                        )
                    )
                    .frame(width: decorationSize, height: decorationSize)
                    .blur(radius: 2)
            } else {
                // Soft spark
                Image(systemName: "sparkle")
                    .font(.system(size: decorationSize * 0.8))
                    .foregroundStyle(palette.accentSecondary.opacity(intensity.opacity))
            }

        case .treehouse:
            // Leaves and acorns
            if index % 3 == 0 {
                Image(systemName: "leaf.fill")
                    .font(.system(size: decorationSize))
                    .foregroundStyle(palette.accentSecondary.opacity(intensity.opacity))
            } else if index % 3 == 1 {
                // Small circle like a seed
                Circle()
                    .fill(palette.accent.opacity(intensity.opacity))
                    .frame(width: decorationSize * 0.6, height: decorationSize * 0.6)
            } else {
                Image(systemName: "leaf")
                    .font(.system(size: decorationSize * 0.8))
                    .foregroundStyle(palette.accent.opacity(intensity.opacity))
            }

        case .blanketFort:
            // Soft hearts and stars
            if index % 3 == 0 {
                Image(systemName: "heart.fill")
                    .font(.system(size: decorationSize * 0.8))
                    .foregroundStyle(palette.accentSecondary.opacity(intensity.opacity))
            } else if index % 3 == 1 {
                Image(systemName: "star.fill")
                    .font(.system(size: decorationSize * 0.7))
                    .foregroundStyle(palette.accent.opacity(intensity.opacity))
            } else {
                // Soft pillow shape (rounded rectangle)
                RoundedRectangle(cornerRadius: decorationSize * 0.3)
                    .fill(palette.accent.opacity(intensity.opacity * 0.6))
                    .frame(width: decorationSize * 1.2, height: decorationSize * 0.8)
            }

        case .starlight:
            // Stars and moons
            if index % 4 == 0 {
                Image(systemName: "star.fill")
                    .font(.system(size: decorationSize))
                    .foregroundStyle(palette.accentSecondary.opacity(intensity.opacity))
            } else if index % 4 == 1 {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: decorationSize * 0.9))
                    .foregroundStyle(palette.accent.opacity(intensity.opacity * 0.8))
            } else if index % 4 == 2 {
                Image(systemName: "sparkle")
                    .font(.system(size: decorationSize * 0.7))
                    .foregroundStyle(palette.accentSecondary.opacity(intensity.opacity))
            } else {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [palette.accentSecondary.opacity(intensity.opacity), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: decorationSize / 2
                        )
                    )
                    .frame(width: decorationSize, height: decorationSize)
            }
        }
    }

    private func startAnimation() {
        let duration = Double.random(in: 8...15)
        let xRange: CGFloat = 20
        let yRange: CGFloat = 30

        // Gentle floating motion
        withAnimation(
            .easeInOut(duration: duration)
            .repeatForever(autoreverses: true)
        ) {
            offset = CGSize(
                width: CGFloat.random(in: -xRange...xRange),
                height: CGFloat.random(in: -yRange...yRange)
            )
        }

        // Slow rotation
        withAnimation(
            .linear(duration: duration * 2)
            .repeatForever(autoreverses: false)
        ) {
            rotation = index % 2 == 0 ? 360 : -360
        }

        // Gentle scale pulse
        withAnimation(
            .easeInOut(duration: duration * 0.5)
            .repeatForever(autoreverses: true)
        ) {
            scale = CGFloat.random(in: 0.85...1.15)
        }
    }
}

// MARK: - Organic Blob Background

/// Soft, organic blob shapes that add warmth to backgrounds
struct OrganicBlobBackground: View {
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @State private var animateBlob = false

    var body: some View {
        let palette = appEnvironment.activeProfile.theme.kidPalette

        GeometryReader { geo in
            ZStack {
                // Large soft blob top-right
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                palette.accent.opacity(0.08),
                                palette.accent.opacity(0.02),
                                .clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: geo.size.width * 0.4
                        )
                    )
                    .frame(width: geo.size.width * 0.8, height: geo.size.width * 0.6)
                    .offset(x: geo.size.width * 0.3, y: -geo.size.height * 0.1)
                    .scaleEffect(animateBlob ? 1.05 : 0.95)

                // Medium blob bottom-left
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                palette.accentSecondary.opacity(0.06),
                                palette.accentSecondary.opacity(0.02),
                                .clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: geo.size.width * 0.3
                        )
                    )
                    .frame(width: geo.size.width * 0.6, height: geo.size.width * 0.5)
                    .offset(x: -geo.size.width * 0.25, y: geo.size.height * 0.35)
                    .scaleEffect(animateBlob ? 0.95 : 1.05)

                // Small accent blob
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                palette.accent.opacity(0.05),
                                .clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: geo.size.width * 0.15
                        )
                    )
                    .frame(width: geo.size.width * 0.3, height: geo.size.width * 0.3)
                    .offset(x: -geo.size.width * 0.1, y: -geo.size.height * 0.3)
                    .scaleEffect(animateBlob ? 1.1 : 0.9)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(
                .easeInOut(duration: 12)
                .repeatForever(autoreverses: true)
            ) {
                animateBlob = true
            }
        }
    }
}

// MARK: - Glow Effect

/// Adds a soft, warm glow around content
struct GlowEffect: ViewModifier {
    @EnvironmentObject private var appEnvironment: AppEnvironment
    let intensity: GlowIntensity

    enum GlowIntensity {
        case soft
        case medium
        case warm

        var radius: CGFloat {
            switch self {
            case .soft: return 12
            case .medium: return 20
            case .warm: return 30
            }
        }

        var opacity: Double {
            switch self {
            case .soft: return 0.15
            case .medium: return 0.25
            case .warm: return 0.35
            }
        }
    }

    func body(content: Content) -> some View {
        let palette = appEnvironment.activeProfile.theme.kidPalette
        content
            .shadow(color: palette.accent.opacity(intensity.opacity), radius: intensity.radius)
            .shadow(color: palette.accent.opacity(intensity.opacity * 0.5), radius: intensity.radius * 2)
    }
}

extension View {
    func nookGlow(_ intensity: GlowEffect.GlowIntensity = .soft) -> some View {
        modifier(GlowEffect(intensity: intensity))
    }
}

// MARK: - Cozy Card Style

/// A card style with soft edges, warm shadows, and subtle glow
struct CozyCardStyle: ViewModifier {
    @EnvironmentObject private var appEnvironment: AppEnvironment
    let cornerRadius: CGFloat
    let elevation: CardElevation

    enum CardElevation {
        case flat
        case raised
        case floating

        var shadowRadius: CGFloat {
            switch self {
            case .flat: return 4
            case .raised: return 12
            case .floating: return 24
            }
        }

        var shadowY: CGFloat {
            switch self {
            case .flat: return 2
            case .raised: return 6
            case .floating: return 12
            }
        }
    }

    init(cornerRadius: CGFloat = 24, elevation: CardElevation = .raised) {
        self.cornerRadius = cornerRadius
        self.elevation = elevation
    }

    func body(content: Content) -> some View {
        let palette = appEnvironment.activeProfile.theme.kidPalette
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(palette.cardFill)
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(palette.cardStroke, lineWidth: 1)
            )
            .shadow(color: palette.accent.opacity(0.06), radius: elevation.shadowRadius, y: elevation.shadowY)
            .shadow(color: palette.accent.opacity(0.03), radius: elevation.shadowRadius * 2, y: elevation.shadowY * 1.5)
    }
}

extension View {
    func cozyCard(cornerRadius: CGFloat = 24, elevation: CozyCardStyle.CardElevation = .raised) -> some View {
        modifier(CozyCardStyle(cornerRadius: cornerRadius, elevation: elevation))
    }
}

// MARK: - Bouncy Button Style

/// A playful button style with bounce animation
struct BouncyButtonStyle: ButtonStyle {
    @EnvironmentObject private var appEnvironment: AppEnvironment
    let style: BouncyStyle

    enum BouncyStyle {
        case primary
        case secondary
        case icon
    }

    func makeBody(configuration: Configuration) -> some View {
        let palette = appEnvironment.activeProfile.theme.kidPalette

        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(
                .spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0),
                value: configuration.isPressed
            )
            .onChange(of: configuration.isPressed) { pressed in
                if pressed {
                    HapticService.light()
                }
            }
    }
}

// MARK: - Nook App Background (Enhanced)

/// Enhanced app background with organic blobs and floating decorations
struct NookAppBackground: View {
    @EnvironmentObject private var appEnvironment: AppEnvironment
    let showDecorations: Bool
    let decorationIntensity: FloatingDecorations.DecorationIntensity

    init(showDecorations: Bool = true, decorationIntensity: FloatingDecorations.DecorationIntensity = .gentle) {
        self.showDecorations = showDecorations
        self.decorationIntensity = decorationIntensity
    }

    var body: some View {
        ZStack {
            // Base gradient
            appEnvironment.activeProfile.theme.kidPalette.backgroundGradient

            // Organic blobs
            OrganicBlobBackground()

            // Floating decorations
            if showDecorations {
                FloatingDecorations(intensity: decorationIntensity)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Playful Icon Button

/// Large, clearly labeled icon button for kids
struct PlayfulIconButton: View {
    @EnvironmentObject private var appEnvironment: AppEnvironment
    let icon: String
    let label: String
    let isActive: Bool
    let action: () -> Void

    init(icon: String, label: String, isActive: Bool = false, action: @escaping () -> Void) {
        self.icon = icon
        self.label = label
        self.isActive = isActive
        self.action = action
    }

    var body: some View {
        let palette = appEnvironment.activeProfile.theme.kidPalette

        Button(action: {
            HapticService.selection()
            action()
        }) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isActive ? palette.accent : palette.cardFill)
                        .frame(width: 64, height: 64)

                    if isActive {
                        Circle()
                            .stroke(palette.accentSecondary, lineWidth: 3)
                            .frame(width: 64, height: 64)
                    }

                    Image(systemName: icon)
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(isActive ? .white : palette.accent)
                }
                .shadow(color: palette.accent.opacity(isActive ? 0.3 : 0.1), radius: isActive ? 12 : 6, y: 4)

                Text(label)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(isActive ? palette.accent : .secondary)
            }
        }
        .buttonStyle(BouncyButtonStyle(style: .icon))
    }
}
