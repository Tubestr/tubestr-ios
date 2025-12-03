//
//  KidTheme.swift
//  MyTube
//
//  Created by Codex on 11/29/25.
//

import SwiftUI
import UIKit

struct KidPalette {
    let accent: Color
    let accentSecondary: Color
    let bgTop: Color
    let bgBottom: Color
    let cardFill: Color
    let cardStroke: Color
    let chipFill: Color
    let success: Color
    let warning: Color
    let error: Color

    var backgroundGradient: LinearGradient {
        LinearGradient(colors: [bgTop, bgBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension ThemeDescriptor {
    var kidPalette: KidPalette {
        switch self {
        case .campfire:
            // Warm oranges, deep amber, soft cream - like gathering around a fire
            return KidPalette(
                accent: Color(
                    light: Color(red: 0.91, green: 0.49, blue: 0.27),
                    dark: Color(red: 1.00, green: 0.62, blue: 0.40)
                ),
                accentSecondary: Color(
                    light: Color(red: 1.00, green: 0.72, blue: 0.42),
                    dark: Color(red: 1.00, green: 0.78, blue: 0.55)
                ),
                bgTop: Color(
                    light: Color(red: 1.00, green: 0.97, blue: 0.94),
                    dark: Color(red: 0.18, green: 0.12, blue: 0.08)
                ),
                bgBottom: Color(
                    light: Color(red: 1.00, green: 0.92, blue: 0.86),
                    dark: Color(red: 0.24, green: 0.16, blue: 0.11)
                ),
                cardFill: Color(
                    light: Color.white.opacity(0.7),
                    dark: Color.white.opacity(0.08)
                ),
                cardStroke: Color(
                    light: Color(red: 0.91, green: 0.49, blue: 0.27),
                    dark: Color(red: 1.00, green: 0.62, blue: 0.40)
                ).opacity(0.2),
                chipFill: Color(
                    light: Color.white.opacity(0.8),
                    dark: Color.white.opacity(0.15)
                ),
                success: Color(red: 0.30, green: 0.69, blue: 0.47),
                warning: Color(red: 0.95, green: 0.68, blue: 0.25),
                error: Color(red: 0.90, green: 0.40, blue: 0.38)
            )
        case .treehouse:
            // Warm browns, soft greens, golden yellows - like a cozy treehouse hideaway
            return KidPalette(
                accent: Color(
                    light: Color(red: 0.55, green: 0.45, blue: 0.33),
                    dark: Color(red: 0.71, green: 0.61, blue: 0.47)
                ),
                accentSecondary: Color(
                    light: Color(red: 0.66, green: 0.69, blue: 0.45),
                    dark: Color(red: 0.75, green: 0.76, blue: 0.57)
                ),
                bgTop: Color(
                    light: Color(red: 0.98, green: 0.96, blue: 0.92),
                    dark: Color(red: 0.14, green: 0.12, blue: 0.10)
                ),
                bgBottom: Color(
                    light: Color(red: 0.92, green: 0.89, blue: 0.82),
                    dark: Color(red: 0.20, green: 0.16, blue: 0.14)
                ),
                cardFill: Color(
                    light: Color.white.opacity(0.7),
                    dark: Color.white.opacity(0.08)
                ),
                cardStroke: Color(
                    light: Color(red: 0.55, green: 0.45, blue: 0.33),
                    dark: Color(red: 0.71, green: 0.61, blue: 0.47)
                ).opacity(0.2),
                chipFill: Color(
                    light: Color.white.opacity(0.8),
                    dark: Color.white.opacity(0.15)
                ),
                success: Color(red: 0.30, green: 0.69, blue: 0.47),
                warning: Color(red: 0.95, green: 0.68, blue: 0.25),
                error: Color(red: 0.90, green: 0.40, blue: 0.38)
            )
        case .blanketFort:
            // Soft lavenders, warm pinks, cozy cream - like a magical pillow fort
            return KidPalette(
                accent: Color(
                    light: Color(red: 0.70, green: 0.57, blue: 0.71),
                    dark: Color(red: 0.78, green: 0.67, blue: 0.80)
                ),
                accentSecondary: Color(
                    light: Color(red: 0.90, green: 0.69, blue: 0.73),
                    dark: Color(red: 0.94, green: 0.76, blue: 0.78)
                ),
                bgTop: Color(
                    light: Color(red: 0.99, green: 0.97, blue: 0.99),
                    dark: Color(red: 0.15, green: 0.13, blue: 0.16)
                ),
                bgBottom: Color(
                    light: Color(red: 0.97, green: 0.94, blue: 0.96),
                    dark: Color(red: 0.19, green: 0.16, blue: 0.20)
                ),
                cardFill: Color(
                    light: Color.white.opacity(0.7),
                    dark: Color.white.opacity(0.08)
                ),
                cardStroke: Color(
                    light: Color(red: 0.70, green: 0.57, blue: 0.71),
                    dark: Color(red: 0.78, green: 0.67, blue: 0.80)
                ).opacity(0.2),
                chipFill: Color(
                    light: Color.white.opacity(0.8),
                    dark: Color.white.opacity(0.15)
                ),
                success: Color(red: 0.30, green: 0.69, blue: 0.47),
                warning: Color(red: 0.95, green: 0.68, blue: 0.25),
                error: Color(red: 0.90, green: 0.40, blue: 0.38)
            )
        case .starlight:
            // Deep warm purples, golden stars, midnight warmth - like a cozy night sky
            return KidPalette(
                accent: Color(
                    light: Color(red: 0.47, green: 0.37, blue: 0.59),
                    dark: Color(red: 0.65, green: 0.55, blue: 0.76)
                ),
                accentSecondary: Color(
                    light: Color(red: 0.84, green: 0.73, blue: 0.49),
                    dark: Color(red: 0.92, green: 0.82, blue: 0.61)
                ),
                bgTop: Color(
                    light: Color(red: 0.96, green: 0.95, blue: 0.98),
                    dark: Color(red: 0.12, green: 0.10, blue: 0.18)
                ),
                bgBottom: Color(
                    light: Color(red: 0.92, green: 0.90, blue: 0.96),
                    dark: Color(red: 0.18, green: 0.15, blue: 0.24)
                ),
                cardFill: Color(
                    light: Color.white.opacity(0.7),
                    dark: Color.white.opacity(0.08)
                ),
                cardStroke: Color(
                    light: Color(red: 0.47, green: 0.37, blue: 0.59),
                    dark: Color(red: 0.65, green: 0.55, blue: 0.76)
                ).opacity(0.2),
                chipFill: Color(
                    light: Color.white.opacity(0.8),
                    dark: Color.white.opacity(0.15)
                ),
                success: Color(red: 0.30, green: 0.69, blue: 0.47),
                warning: Color(red: 0.95, green: 0.68, blue: 0.25),
                error: Color(red: 0.90, green: 0.40, blue: 0.38)
            )
        }
    }
}

struct KidAppBackground: View {
    @EnvironmentObject private var appEnvironment: AppEnvironment

    var body: some View {
        appEnvironment.activeProfile.theme.kidPalette.backgroundGradient
            .ignoresSafeArea()
    }
}

struct KidCardBackground: ViewModifier {
    @EnvironmentObject private var appEnvironment: AppEnvironment

    func body(content: Content) -> some View {
        let palette = appEnvironment.activeProfile.theme.kidPalette
        return content
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(palette.cardStroke, lineWidth: 1)
            )
            .shadow(color: palette.accent.opacity(0.06), radius: 14, y: 8)
    }
}

extension View {
    func kidCardBackground() -> some View {
        modifier(KidCardBackground())
    }
}

struct KidPrimaryButtonStyle: ButtonStyle {
    @EnvironmentObject private var appEnvironment: AppEnvironment

    func makeBody(configuration: Configuration) -> some View {
        let palette = appEnvironment.activeProfile.theme.kidPalette
        return configuration.label
            .font(.system(.headline, design: .rounded))
            .foregroundStyle(Color.white)
            .padding(.vertical, 14)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(colors: [palette.accent, palette.accentSecondary], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            )
            .shadow(color: palette.accent.opacity(0.18), radius: 14, y: 8)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.45, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

struct KidSecondaryButtonStyle: ButtonStyle {
    @EnvironmentObject private var appEnvironment: AppEnvironment

    func makeBody(configuration: Configuration) -> some View {
        let palette = appEnvironment.activeProfile.theme.kidPalette
        return configuration.label
            .font(.system(.headline, design: .rounded))
            .foregroundStyle(palette.accent)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(palette.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(palette.cardStroke, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.40, dampingFraction: 0.85), value: configuration.isPressed)
    }
}

struct KidCircleIconButtonStyle: ButtonStyle {
    @EnvironmentObject private var appEnvironment: AppEnvironment

    func makeBody(configuration: Configuration) -> some View {
        let palette = appEnvironment.activeProfile.theme.kidPalette
        return configuration.label
            .frame(width: 56, height: 56)
            .background(
                Circle().fill(
                    LinearGradient(colors: [palette.accent, palette.accentSecondary], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            )
            .foregroundStyle(Color.white)
            .shadow(color: palette.accent.opacity(0.18), radius: 12, y: 7)
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.50, dampingFraction: 0.80), value: configuration.isPressed)
    }
}

extension Color {
    /// Creates a color that dynamically adapts to light and dark modes
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .dark:
                return UIColor(dark)
            default:
                return UIColor(light)
            }
        })
    }
    
    /// Creates a color that dynamically adapts to light and dark modes using UIColors
    init(light: UIColor, dark: UIColor) {
        self.init(uiColor: UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .dark:
                return dark
            default:
                return light
            }
        })
    }
}
