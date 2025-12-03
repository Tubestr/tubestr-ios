//
//  PlayerView.swift
//  MyTube
//
//  Created by Codex on 10/24/25.
//

import AVKit
import SwiftUI

struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: PlayerViewModel
    private let environment: AppEnvironment
    @State private var showingReportSheet = false
    @State private var showingPublishPIN = false
    @State private var showingEditor = false
    @State private var videoForEditing: VideoModel?
    @State private var showControls = true
    @State private var controlsTimer: Timer?

    /// Initialize with a local video
    init(rankedVideo: RankingEngine.RankedVideo, environment: AppEnvironment) {
        self.environment = environment
        _viewModel = StateObject(wrappedValue: PlayerViewModel(rankedVideo: rankedVideo, environment: environment))
    }

    /// Initialize with a remote video
    init(remoteVideo: HomeFeedViewModel.SharedRemoteVideo, environment: AppEnvironment) {
        self.environment = environment
        _viewModel = StateObject(wrappedValue: PlayerViewModel(remoteVideo: remoteVideo, environment: environment))
    }

    var body: some View {
        let palette = environment.activeProfile.theme.kidPalette

        GeometryReader { geometry in
            ZStack {
                // Cozy Theater Background
                theaterBackground(palette: palette, geometry: geometry)

                VStack(spacing: 0) {
                    // Top Bar
                    topBar(palette: palette)
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .opacity(showControls ? 1 : 0)

                    Spacer()

                    // Video Theater Area
                    videoTheaterArea(palette: palette, geometry: geometry)
                        .padding(.horizontal, 40)

                    Spacer()

                    // Bottom Controls Panel
                    bottomControlsPanel(palette: palette)
                        .opacity(showControls ? 1 : 0)
                }
            }
        }
        .onAppear {
            viewModel.onAppear()
            startControlsTimer()
        }
        .onDisappear { viewModel.onDisappear() }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.3)) {
                showControls.toggle()
            }
            if showControls {
                startControlsTimer()
            }
        }
        .sheet(isPresented: $showingReportSheet) {
            FeelingReportSheet(
                isSubmitting: viewModel.isReporting,
                errorMessage: $viewModel.reportError,
                childName: environment.activeProfile.name,
                allowsRelationshipActions: !viewModel.source.isLocal,
                onSubmit: { feeling, action in
                    Task {
                        await viewModel.reportVideoWithFeeling(feeling: feeling, action: action)
                        if viewModel.reportSuccess {
                            showingReportSheet = false
                        }
                    }
                },
                onCancel: {
                    showingReportSheet = false
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingPublishPIN) {
            PINPromptView(title: "Ask Parent to Publish") { pin in
                try await viewModel.publishPendingVideo(pin: pin)
            }
        }
        .fullScreenCover(isPresented: $showingEditor) {
            if let video = videoForEditing {
                EditorDetailView(video: video, environment: environment)
            }
        }
        .statusBar(hidden: true)
    }

    // MARK: - Theater Background

    private func theaterBackground(palette: KidPalette, geometry: GeometryProxy) -> some View {
        ZStack {
            // Dark warm base
            Color(red: 0.08, green: 0.06, blue: 0.10)

            // Warm ambient glow from video area
            RadialGradient(
                colors: [
                    palette.accent.opacity(0.15),
                    palette.accent.opacity(0.05),
                    .clear
                ],
                center: .center,
                startRadius: 100,
                endRadius: geometry.size.width * 0.8
            )

            // Subtle floating decorations for theater ambiance
            FloatingDecorations(intensity: .subtle)
                .opacity(0.5)
        }
        .ignoresSafeArea()
    }

    // MARK: - Top Bar

    private func topBar(palette: KidPalette) -> some View {
        HStack(spacing: 16) {
            // Close Button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(
                        Circle()
                            .fill(.white.opacity(0.15))
                            .background(.ultraThinMaterial, in: Circle())
                    )
            }

            Spacer()

            // Edit Button
            if viewModel.canEdit {
                Button {
                    if let video = viewModel.videoModelForEditing() {
                        videoForEditing = video
                        showingEditor = true
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 16, weight: .semibold))
                        Text(viewModel.source.isLocal ? "Edit" : "Remix")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(.white.opacity(0.15))
                            .background(.ultraThinMaterial, in: Capsule())
                    )
                }
            }

            // Publish Button
            if viewModel.shouldShowPublishAction {
                Button {
                    showingPublishPIN = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text(viewModel.isPublishing ? "Publishing..." : "Publish")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(palette.accent)
                    )
                    .nookGlow(.soft)
                }
                .disabled(viewModel.isPublishing)
            }

            // Report Button
            Button {
                viewModel.reportError = nil
                showingReportSheet = true
            } label: {
                Image(systemName: "flag")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 48, height: 48)
                    .background(
                        Circle()
                            .fill(.white.opacity(0.1))
                    )
            }
        }
    }

    // MARK: - Video Theater Area

    private func videoTheaterArea(palette: KidPalette, geometry: GeometryProxy) -> some View {
        ZStack {
            // Theater "frame" glow
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(palette.accent.opacity(0.1))
                .blur(radius: 40)
                .padding(-20)

            if let player = viewModel.player {
                VideoPlayer(player: player)
                    .aspectRatio(viewModel.videoAspectRatio, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [palette.accent.opacity(0.4), palette.accentSecondary.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 3
                            )
                    )
                    .shadow(color: palette.accent.opacity(0.3), radius: 30, y: 15)
                    .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
            } else {
                // Loading/Error State
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.white.opacity(0.05))
                    .aspectRatio(viewModel.videoAspectRatio, contentMode: .fit)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(palette.accent.opacity(0.2), lineWidth: 2)
                    )
                    .overlay(loadingOrErrorOverlay(palette: palette))
            }

            // Big play/pause overlay (shows when paused)
            if !viewModel.isPlaying && viewModel.player != nil && showControls {
                Button {
                    viewModel.togglePlayPause()
                    startControlsTimer()
                } label: {
                    ZStack {
                        Circle()
                            .fill(.black.opacity(0.4))
                            .frame(width: 100, height: 100)
                            .blur(radius: 10)

                        Circle()
                            .fill(palette.accent)
                            .frame(width: 80, height: 80)

                        Image(systemName: "play.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.white)
                            .offset(x: 3)
                    }
                    .nookGlow(.warm)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private func loadingOrErrorOverlay(palette: KidPalette) -> some View {
        VStack(spacing: 16) {
            if let error = viewModel.playbackError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(palette.warning)

                Text(error)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(palette.accent)
                    .scaleEffect(1.5)

                Text("Loading your video...")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    // MARK: - Bottom Controls Panel

    private func bottomControlsPanel(palette: KidPalette) -> some View {
        VStack(spacing: 20) {
            // Title and Like
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(viewModel.title)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Text(viewModel.subtitle)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }

                Spacer()

                // Like Button
                if viewModel.canLike {
                    Button {
                        HapticService.selection()
                        viewModel.toggleLike()
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(viewModel.isLiked ? Color.pink : .white.opacity(0.15))
                                    .frame(width: 56, height: 56)

                                Image(systemName: viewModel.isLiked ? "heart.fill" : "heart")
                                    .font(.system(size: 24))
                                    .foregroundStyle(viewModel.isLiked ? .white : .white.opacity(0.9))
                            }
                            .shadow(color: viewModel.isLiked ? Color.pink.opacity(0.5) : .clear, radius: 12)

                            if viewModel.likeCount > 0 {
                                Text("\(viewModel.likeCount)")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                        }
                    }
                }
            }

            // Progress Scrubber
            VStack(spacing: 8) {
                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Track
                        Capsule()
                            .fill(.white.opacity(0.2))
                            .frame(height: 6)

                        // Progress
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [palette.accent, palette.accentSecondary],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * viewModel.progress, height: 6)

                        // Scrubber thumb
                        Circle()
                            .fill(.white)
                            .frame(width: 16, height: 16)
                            .shadow(color: palette.accent.opacity(0.5), radius: 6)
                            .offset(x: (geo.size.width * viewModel.progress) - 8)
                    }
                }
                .frame(height: 16)

                // Time labels
                HStack {
                    Text(timeString(viewModel.progress * viewModel.duration))
                        .font(.system(size: 13, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))

                    Spacer()

                    Text(viewModel.formattedDuration)
                        .font(.system(size: 13, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            // Playback Controls
            HStack(spacing: 48) {
                // Rewind
                Button {
                    viewModel.player?.seek(to: .zero)
                    startControlsTimer()
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 48, height: 48)
                }
                .disabled(viewModel.player == nil)

                // Play/Pause
                Button {
                    viewModel.togglePlayPause()
                    startControlsTimer()
                } label: {
                    ZStack {
                        Circle()
                            .fill(palette.accent)
                            .frame(width: 72, height: 72)

                        Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white)
                            .offset(x: viewModel.isPlaying ? 0 : 2)
                    }
                    .shadow(color: palette.accent.opacity(0.4), radius: 16, y: 4)
                }
                .disabled(viewModel.player == nil)

                // Forward placeholder
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.white.opacity(0.3))
                    .frame(width: 48, height: 48)
            }
        }
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                )
        )
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    // MARK: - Helpers

    private func timeString(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: seconds) ?? "0:00"
    }

    private func startControlsTimer() {
        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { _ in
            if viewModel.isPlaying {
                withAnimation(.easeOut(duration: 0.3)) {
                    showControls = false
                }
            }
        }
    }
}

