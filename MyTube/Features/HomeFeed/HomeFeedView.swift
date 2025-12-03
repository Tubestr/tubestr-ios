//
//  HomeFeedView.swift
//  MyTube
//
//  Created by Codex on 10/24/25.
//

import SwiftUI
import UIKit

struct HomeFeedView: View {
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @StateObject private var viewModel = HomeFeedViewModel()
    @State private var selectedVideo: RankingEngine.RankedVideo?
    @State private var showingTrustedCreatorsInfo = false
    @Namespace private var heroNamespace

    var body: some View {
        let palette = appEnvironment.activeProfile.theme.kidPalette

        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Welcome Header
                    welcomeHeader
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .padding(.bottom, 24)

                    // Main Content
                    if viewModel.rankedVideos.isEmpty && viewModel.sharedSections.isEmpty {
                        emptyStateCard
                            .padding(.horizontal, 24)
                            .padding(.vertical, 40)
                    } else {
                        // Shared Videos Section (Friends & Family first)
                        if !viewModel.sharedSections.isEmpty {
                            sharedVideosSection
                                .padding(.bottom, 32)
                        }

                        // My Videos Grid
                        if !viewModel.rankedVideos.isEmpty {
                            myVideosSection
                                .padding(.bottom, 32)
                        }
                    }

                    // Add Friends CTA
                    addFriendsCTA
                        .padding(.horizontal, 24)
                        .padding(.bottom, 40)
                }
            }
            .refreshable {
                await viewModel.refresh()
            }
            .background(NookAppBackground(showDecorations: true, decorationIntensity: .gentle))
            .standardToolbar(showLogo: true)
        }
        .fullScreenCover(item: $selectedVideo) { rankedVideo in
            PlayerView(rankedVideo: rankedVideo, environment: appEnvironment)
        }
        .fullScreenCover(
            item: Binding(
                get: { viewModel.presentedRemoteVideo },
                set: { viewModel.presentedRemoteVideo = $0 }
            )
        ) { remoteVideo in
            PlayerView(remoteVideo: remoteVideo, environment: appEnvironment)
        }
        .onAppear {
            viewModel.bind(to: appEnvironment)
        }
        .alert("Add Trusted Creators", isPresented: $showingTrustedCreatorsInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Ask a parent to open Parent Zone → Connections to scan a connection invite or approve a trusted family.")
        }
    }

    // MARK: - Welcome Header

    private var welcomeHeader: some View {
        let palette = appEnvironment.activeProfile.theme.kidPalette
        let greeting = greetingText

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(greeting)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(palette.accent)

                    Text("What will you create today?")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Profile avatar with glow
                Circle()
                    .fill(palette.accent.opacity(0.2))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(palette.accent)
                    )
                    .nookGlow(.soft)
            }
        }
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let name = appEnvironment.activeProfile.name
        if hour < 12 {
            return "Good morning, \(name)!"
        } else if hour < 17 {
            return "Good afternoon, \(name)!"
        } else {
            return "Good evening, \(name)!"
        }
    }

    // MARK: - My Videos Section

    private var myVideosSection: some View {
        let palette = appEnvironment.activeProfile.theme.kidPalette

        return VStack(alignment: .leading, spacing: 16) {
            // Section Header
            HStack {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(palette.accent)

                Text("My Videos")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(viewModel.rankedVideos.count)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(palette.accent.opacity(0.15), in: Capsule())
            }
            .padding(.horizontal, 24)

            // Grid Gallery
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ],
                spacing: 20
            ) {
                ForEach(viewModel.rankedVideos) { rankedVideo in
                    VideoTile(
                        video: rankedVideo.video,
                        image: loadThumbnail(for: rankedVideo.video),
                        onTap: { selectedVideo = rankedVideo }
                    )
                }
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Shared Videos Section

    private var sharedVideosSection: some View {
        let palette = appEnvironment.activeProfile.theme.kidPalette

        return VStack(alignment: .leading, spacing: 16) {
            // Section Header
            HStack {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(palette.accentSecondary)

                Text("From Friends & Family")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer()
            }
            .padding(.horizontal, 24)

            // Shared Videos by Creator
            ForEach(viewModel.sharedSections) { section in
                VStack(alignment: .leading, spacing: 12) {
                    Text(section.title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 24)

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 16) {
                            ForEach(section.videos) { item in
                                SharedVideoTile(
                                    video: item,
                                    image: loadRemoteThumbnail(for: item.video),
                                    onTap: { viewModel.handleRemoteVideoTap(item) }
                                )
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateCard: some View {
        let palette = appEnvironment.activeProfile.theme.kidPalette

        return VStack(spacing: 24) {
            // Animated illustration area
            ZStack {
                Circle()
                    .fill(palette.accent.opacity(0.1))
                    .frame(width: 140, height: 140)

                Circle()
                    .fill(palette.accent.opacity(0.15))
                    .frame(width: 100, height: 100)

                Image(systemName: "video.badge.plus")
                    .font(.system(size: 48))
                    .foregroundStyle(palette.accent)
            }
            .nookGlow(.medium)

            VStack(spacing: 8) {
                Text("Your Nook awaits!")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Capture your first video to start\nfilling your cozy corner")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .cozyCard(cornerRadius: 32, elevation: .floating)
    }

    // MARK: - Add Friends CTA

    private var addFriendsCTA: some View {
        let palette = appEnvironment.activeProfile.theme.kidPalette

        return Button {
            showingTrustedCreatorsInfo = true
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(palette.accentSecondary.opacity(0.2))
                        .frame(width: 48, height: 48)

                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 22))
                        .foregroundStyle(palette.accentSecondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Add Friends & Family")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("Share videos with people you trust")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.accent.opacity(0.6))
            }
            .padding(20)
            .cozyCard(cornerRadius: 24, elevation: .raised)
        }
        .buttonStyle(BouncyButtonStyle(style: .secondary))
    }

    // MARK: - Helpers

    private func loadThumbnail(for video: VideoModel) -> UIImage? {
        let url = appEnvironment.videoLibrary.thumbnailFileURL(for: video)
        return UIImage(contentsOfFile: url.path)
    }

    private func loadRemoteThumbnail(for video: RemoteVideoModel) -> UIImage? {
        guard let url = video.localThumbURL(root: appEnvironment.storagePaths.rootURL) else {
            return nil
        }
        return UIImage(contentsOfFile: url.path)
    }
}

// MARK: - Video Tile (Grid Item)

private struct VideoTile: View {
    @EnvironmentObject private var appEnvironment: AppEnvironment
    let video: VideoModel
    let image: UIImage?
    let onTap: () -> Void

    @State private var isPressed = false

    private var palette: KidPalette { appEnvironment.activeProfile.theme.kidPalette }
    private var isPending: Bool { video.approvalStatus == .pending }

    /// Compute aspect ratio from the thumbnail image
    private var aspectRatio: CGFloat {
        guard let image else { return 1.0 }
        guard image.size.height > 0 else { return 1.0 }
        return image.size.width / image.size.height
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                // Thumbnail
                ZStack(alignment: .topTrailing) {
                    // Background
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(palette.cardFill)

                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        VStack {
                            Image(systemName: "video.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(palette.accent.opacity(0.4))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    // Badges
                    VStack(alignment: .trailing, spacing: 6) {
                        if video.liked {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.white)
                                .padding(8)
                                .background(Color.pink, in: Circle())
                                .shadow(radius: 4)
                        }

                        if isPending {
                            Text("Pending")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(palette.accent, in: Capsule())
                        }
                    }
                    .padding(10)
                }
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(palette.cardStroke, lineWidth: 1)
                )
                .shadow(color: palette.accent.opacity(0.08), radius: 12, y: 6)

                // Title
                Text(video.title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
        }
        .buttonStyle(BouncyButtonStyle(style: .secondary))
    }
}

// MARK: - Shared Video Tile

private struct SharedVideoTile: View {
    @EnvironmentObject private var appEnvironment: AppEnvironment
    let video: HomeFeedViewModel.SharedRemoteVideo
    let image: UIImage?
    let onTap: () -> Void

    private var palette: KidPalette { appEnvironment.activeProfile.theme.kidPalette }
    private var status: RemoteVideoModel.Status { video.video.statusValue }

    private var statusIcon: String {
        switch status {
        case .available: return "arrow.down.circle.fill"
        case .downloading: return "arrow.triangle.2.circlepath"
        case .downloaded: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        case .revoked: return "xmark.circle.fill"
        case .deleted: return "trash.circle.fill"
        case .blocked: return "hand.raised.circle.fill"
        case .reported: return "exclamationmark.bubble.fill"
        }
    }

    private var statusColor: Color {
        switch status {
        case .available: return palette.accentSecondary
        case .downloading: return palette.accent
        case .downloaded: return palette.success
        case .failed, .revoked, .deleted, .blocked: return palette.error
        case .reported: return palette.warning
        }
    }

    private var isActionable: Bool {
        switch status {
        case .available, .failed, .downloaded: return true
        default: return false
        }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                // Thumbnail
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(palette.cardFill)

                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "cloud.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(palette.accent.opacity(0.4))
                    }

                    if status == .downloading {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.2)
                    }
                }
                .frame(width: 160, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(statusColor.opacity(0.3), lineWidth: 2)
                )
                // Status badge outside clip area
                .overlay(alignment: .bottomLeading) {
                    Image(systemName: statusIcon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(statusColor)
                        .padding(6)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(8)
                }
                .shadow(color: palette.accent.opacity(0.08), radius: 12, y: 6)

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(video.video.title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text("From \(video.ownerDisplayName)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(width: 160, alignment: .leading)
            }
        }
        .buttonStyle(BouncyButtonStyle(style: .secondary))
        .disabled(!isActionable)
        .opacity(isActionable ? 1.0 : 0.6)
    }
}

