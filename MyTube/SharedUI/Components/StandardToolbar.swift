//
//  StandardToolbar.swift
//  MyTube
//
//  Created by Codex on 11/29/25.
//

import SwiftUI

struct StandardToolbar: ViewModifier {
    let showLogo: Bool
    @EnvironmentObject private var appEnvironment: AppEnvironment

    func body(content: Content) -> some View {
        content.toolbar {
            if showLogo {
                ToolbarItem(placement: .navigationBarLeading) {
                    Text("Nook")
                        .font(.system(.title2, design: .rounded).weight(.heavy))
                        .foregroundStyle(appEnvironment.activeProfile.theme.kidPalette.accent)
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                ProfileSwitcherButton()
            }
        }
    }
}

extension View {
    func standardToolbar(showLogo: Bool = false) -> some View {
        modifier(StandardToolbar(showLogo: showLogo))
    }
}

