//
//  AppRootView.swift
//  MyTube
//
//  Created by Codex on 10/24/25.
//

import SwiftUI

struct AppRootView: View {
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @State private var selection: Route = .home

    var body: some View {
        Group {
            switch appEnvironment.onboardingState {
            case .needsParentIdentity:
                OnboardingFlowView(environment: appEnvironment)
            case .ready:
                ZStack(alignment: .bottom) {
                    TabView(selection: $selection) {
                        HomeFeedView()
                            .toolbar(.hidden, for: .tabBar)
                            .tag(Route.home)

                        CaptureView(environment: appEnvironment)
                            .toolbar(.hidden, for: .tabBar)
                            .tag(Route.capture)

                        NavigationStack {
                            EditorHubView(environment: appEnvironment)
                        }
                        .toolbar(.hidden, for: .tabBar)
                        .tag(Route.editor)

                        ParentZoneView(environment: appEnvironment)
                            .toolbar(.hidden, for: .tabBar)
                            .tag(Route.parentZone)
                    }
                    
                    CustomTabBar(selection: $selection, accent: appEnvironment.activeProfile.theme.kidPalette.accent)
                }
                .onAppear {
                    if !appEnvironment.parentAuth.isPinConfigured() {
                        selection = .parentZone
                    }
                }
                .onChange(of: appEnvironment.pendingDeepLink) { newValue in
                    if newValue != nil {
                        selection = .parentZone
                    }
                }
            }
        }
        .tint(appEnvironment.activeProfile.theme.kidPalette.accent)
        .background(KidAppBackground())
    }

    enum Route: Hashable {
        case home
        case capture
        case editor
        case parentZone
    }
}

private struct CustomTabBar: View {
    @Binding var selection: AppRootView.Route
    let accent: Color
    
    var body: some View {
        HStack(spacing: 0) {
            tabButton(route: .home, icon: "house.fill", label: "Home")
            divider
            tabButton(route: .capture, icon: "video.badge.plus", label: "Capture")
            divider
            tabButton(route: .editor, icon: "wand.and.stars", label: "Editor")
            divider
            tabButton(route: .parentZone, icon: "lock.shield", label: "Parent Zone")
        }
        .fixedSize(horizontal: false, vertical: true) // Ensure height is determined by content
        .background(
            Rectangle()
                .fill(.ultraThickMaterial)
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(alignment: .top) {
            Divider()
                .background(Color(.separator))
        }
    }
    
    private var divider: some View {
        Rectangle()
            .fill(accent.opacity(0.15))
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .padding(.vertical, 6)
    }
    
    private func tabButton(route: AppRootView.Route, icon: String, label: String) -> some View {
        Button {
            selection = route
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                Text(label)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity) // Equal sized tabs
            .padding(.vertical, 6)
            .foregroundStyle(selection == route ? accent : .primary)
            .contentShape(Rectangle())
            .fontWeight(selection == route ? .bold : .medium)
        }
    }
}
