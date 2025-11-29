//
//  ProfileSwitcherButton.swift
//  MyTube
//
//  Created by Codex on 11/29/25.
//

import SwiftUI
import CoreData

struct ProfileSwitcherButton: View {
    @EnvironmentObject private var appEnvironment: AppEnvironment
    
    // Fetch all profiles sorted by name
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ProfileEntity.name, ascending: true)],
        animation: .default)
    private var profiles: FetchedResults<ProfileEntity>

    var body: some View {
        Menu {
            Section("Switch Profile") {
                ForEach(profiles, id: \.id) { entity in
                    if let profile = ProfileModel(entity: entity) {
                        Button {
                            switchProfile(profile)
                        } label: {
                            if appEnvironment.activeProfile.id == profile.id {
                                Label(profile.name, systemImage: "checkmark")
                            } else {
                                Text(profile.name)
                            }
                        }
                    }
                }
            }
            
            Section("Theme") {
                Picker("Theme", selection: Binding(
                    get: { appEnvironment.activeProfile.theme },
                    set: { newTheme in
                        updateTheme(newTheme)
                    }
                )) {
                    ForEach(ThemeDescriptor.allCases, id: \.self) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
                .pickerStyle(.menu)
            }
        } label: {
            HStack(spacing: 8) {
                Text(appEnvironment.activeProfile.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Image(systemName: "person.crop.circle")
                    .font(.title2)
                    .foregroundStyle(appEnvironment.activeProfile.theme.kidPalette.accent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
        }
    }
    
    private func switchProfile(_ profile: ProfileModel) {
        appEnvironment.switchProfile(profile)
    }
    
    private func updateTheme(_ theme: ThemeDescriptor) {
        var updated = appEnvironment.activeProfile
        updated.theme = theme
        do {
            try appEnvironment.profileStore.updateProfile(updated)
            appEnvironment.switchProfile(updated)
        } catch {
            // In a real app, we'd log this error properly
            print("Failed to update profile theme: \(error)")
        }
    }
}

