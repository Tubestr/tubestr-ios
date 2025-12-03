//
//  PinKeypad.swift
//  MyTube
//
//  Created by Assistant on 11/20/25.
//

import SwiftUI

struct PinKeypad: View {
    @EnvironmentObject private var appEnvironment: AppEnvironment
    let onInput: (String) -> Void
    var isEnabled: Bool = true

    private let keypad: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["⌫", "0", "OK"]
    ]

    private var palette: KidPalette {
        appEnvironment.activeProfile.theme.kidPalette
    }

    var body: some View {
        VStack(spacing: 12) {
            ForEach(keypad, id: \.self) { row in
                HStack(spacing: 12) {
                    ForEach(row, id: \.self) { value in
                        Button {
                            onInput(value)
                        } label: {
                            Text(label(for: value))
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 54)
                                .background(buttonBackground(for: value))
                                .foregroundStyle(.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .disabled(!isEnabled)
                    }
                }
            }
        }
    }

    private func label(for value: String) -> String {
        value == "OK" ? "OK" : value
    }

    private func buttonBackground(for value: String) -> some ShapeStyle {
        if value == "OK" {
            return palette.accent.opacity(0.15)
        } else if value == "⌫" {
            return Color.secondary.opacity(0.12)
        } else {
            return Color(.secondarySystemBackground)
        }
    }
}



