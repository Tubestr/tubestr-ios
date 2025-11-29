//
//  HapticService.swift
//  MyTube
//
//  Created for EditorUXImprovements
//

import UIKit

/// Provides tactile haptic feedback for user interactions.
/// Use these methods to make the app feel responsive and "real" for kids.
enum HapticService {
    /// Light impact for subtle interactions like filter chip taps
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Medium impact for more substantial interactions like sticker selection
    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Selection feedback for tool tab changes and slider scrubbing
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Success notification for export completion
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Error notification for validation failures
    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}

