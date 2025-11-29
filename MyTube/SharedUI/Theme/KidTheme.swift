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
        case .ocean:
            return KidPalette(
                accent: Color(
                    light: Color(red: 0.13, green: 0.66, blue: 0.98),
                    dark: Color(red: 0.30, green: 0.80, blue: 1.00)
                ),
                accentSecondary: Color(
                    light: Color(red: 0.35, green: 0.89, blue: 0.98),
                    dark: Color(red: 0.20, green: 0.70, blue: 0.90)
                ),
                bgTop: Color(
                    light: Color(red: 0.93, green: 0.92, blue: 1.00),
                    dark: Color(red: 0.05, green: 0.05, blue: 0.15)
                ),
                bgBottom: Color(
                    light: Color(red: 0.87, green: 0.90, blue: 1.00),
                    dark: Color(red: 0.10, green: 0.10, blue: 0.25)
                ),
                cardFill: Color(
                    light: Color.white.opacity(0.6),
                    dark: Color.white.opacity(0.1)
                ),
                cardStroke: Color(
                    light: Color(red: 0.13, green: 0.66, blue: 0.98),
                    dark: Color(red: 0.30, green: 0.80, blue: 1.00)
                ).opacity(0.25),
                chipFill: Color(
                    light: Color.white.opacity(0.75),
                    dark: Color.white.opacity(0.2)
                ),
                success: Color(red: 0.18, green: 0.73, blue: 0.43),
                warning: Color(red: 1.00, green: 0.62, blue: 0.00),
                error: Color(red: 0.95, green: 0.33, blue: 0.36)
            )
        case .sunset:
            return KidPalette(
                accent: Color(
                    light: Color(red: 0.97, green: 0.35, blue: 0.54),
                    dark: Color(red: 1.00, green: 0.50, blue: 0.70)
                ),
                accentSecondary: Color(
                    light: Color(red: 1.00, green: 0.68, blue: 0.37),
                    dark: Color(red: 1.00, green: 0.55, blue: 0.20)
                ),
                bgTop: Color(
                    light: Color(red: 1.00, green: 0.90, blue: 0.80),
                    dark: Color(red: 0.25, green: 0.10, blue: 0.05)
                ),
                bgBottom: Color(
                    light: Color(red: 1.00, green: 0.78, blue: 0.72),
                    dark: Color(red: 0.30, green: 0.15, blue: 0.10)
                ),
                cardFill: Color(
                    light: Color.white.opacity(0.6),
                    dark: Color.white.opacity(0.1)
                ),
                cardStroke: Color(
                    light: Color(red: 0.97, green: 0.35, blue: 0.54),
                    dark: Color(red: 1.00, green: 0.50, blue: 0.70)
                ).opacity(0.25),
                chipFill: Color(
                    light: Color.white.opacity(0.75),
                    dark: Color.white.opacity(0.2)
                ),
                success: Color(red: 0.18, green: 0.73, blue: 0.43),
                warning: Color(red: 1.00, green: 0.62, blue: 0.00),
                error: Color(red: 0.95, green: 0.33, blue: 0.36)
            )
        case .forest:
            return KidPalette(
                accent: Color(
                    light: Color(red: 0.25, green: 0.70, blue: 0.49),
                    dark: Color(red: 0.40, green: 0.90, blue: 0.60)
                ),
                accentSecondary: Color(
                    light: Color(red: 0.52, green: 0.88, blue: 0.52),
                    dark: Color(red: 0.30, green: 0.70, blue: 0.40)
                ),
                bgTop: Color(
                    light: Color(red: 0.88, green: 0.98, blue: 0.90),
                    dark: Color(red: 0.05, green: 0.15, blue: 0.05)
                ),
                bgBottom: Color(
                    light: Color(red: 0.80, green: 0.94, blue: 0.86),
                    dark: Color(red: 0.10, green: 0.20, blue: 0.15)
                ),
                cardFill: Color(
                    light: Color.white.opacity(0.6),
                    dark: Color.white.opacity(0.1)
                ),
                cardStroke: Color(
                    light: Color(red: 0.25, green: 0.70, blue: 0.49),
                    dark: Color(red: 0.40, green: 0.90, blue: 0.60)
                ).opacity(0.25),
                chipFill: Color(
                    light: Color.white.opacity(0.75),
                    dark: Color.white.opacity(0.2)
                ),
                success: Color(red: 0.18, green: 0.73, blue: 0.43),
                warning: Color(red: 1.00, green: 0.62, blue: 0.00),
                error: Color(red: 0.95, green: 0.33, blue: 0.36)
            )
        case .galaxy:
            return KidPalette(
                accent: Color(
                    light: Color(red: 0.52, green: 0.46, blue: 0.98),
                    dark: Color(red: 0.70, green: 0.65, blue: 1.00)
                ),
                accentSecondary: Color(
                    light: Color(red: 0.36, green: 0.79, blue: 0.98),
                    dark: Color(red: 0.50, green: 0.40, blue: 0.90)
                ),
                bgTop: Color(
                    light: Color(red: 0.93, green: 0.92, blue: 1.00),
                    dark: Color(red: 0.10, green: 0.05, blue: 0.20)
                ),
                bgBottom: Color(
                    light: Color(red: 0.87, green: 0.90, blue: 1.00),
                    dark: Color(red: 0.15, green: 0.10, blue: 0.30)
                ),
                cardFill: Color(
                    light: Color.white.opacity(0.6),
                    dark: Color.white.opacity(0.1)
                ),
                cardStroke: Color(
                    light: Color(red: 0.52, green: 0.46, blue: 0.98),
                    dark: Color(red: 0.70, green: 0.65, blue: 1.00)
                ).opacity(0.25),
                chipFill: Color(
                    light: Color.white.opacity(0.75),
                    dark: Color.white.opacity(0.2)
                ),
                success: Color(red: 0.18, green: 0.73, blue: 0.43),
                warning: Color(red: 1.00, green: 0.62, blue: 0.00),
                error: Color(red: 0.95, green: 0.33, blue: 0.36)
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
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(palette.cardStroke, lineWidth: 1)
            )
            .shadow(color: palette.accent.opacity(0.08), radius: 10, y: 6)
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
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(colors: [palette.accent, palette.accentSecondary], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            )
            .shadow(color: palette.accent.opacity(0.25), radius: 10, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.85), value: configuration.isPressed)
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
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(palette.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(palette.cardStroke, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.9), value: configuration.isPressed)
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
            .shadow(color: palette.accent.opacity(0.25), radius: 8, y: 5)
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
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
