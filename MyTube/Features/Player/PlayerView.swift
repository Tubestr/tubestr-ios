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
        
        ZStack {
            // Background
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 12) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    
                    Spacer()
                    
                    if viewModel.canEdit {
                        Button {
                            if let video = viewModel.videoModelForEditing() {
                                videoForEditing = video
                                showingEditor = true
                            }
                        } label: {
                            Label(viewModel.source.isLocal ? "Edit" : "Remix", systemImage: "wand.and.stars")
                                .font(.subheadline.bold())
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(.ultraThinMaterial, in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                    
                    if viewModel.shouldShowPublishAction {
                        Button {
                            showingPublishPIN = true
                        } label: {
                            Label(viewModel.isPublishing ? "Publishing..." : "Publish", systemImage: "paperplane.fill")
                                .font(.subheadline.bold())
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(palette.accent, in: Capsule())
                                .foregroundStyle(.white)
                        }
                        .disabled(viewModel.isPublishing)
                    }
                    
                    ReportButtonChip {
                        viewModel.reportError = nil
                        showingReportSheet = true
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                
                Spacer()
                
                // Video Area
                videoPlayerArea
                    .padding(.horizontal)
                
                Spacer()
                
                // Bottom Controls
                VStack(spacing: 20) {
                    // Title and Likes
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(viewModel.title)
                                .font(.title3.bold())
                                .foregroundStyle(.white)
                                .lineLimit(2)
                            
                            Text(viewModel.subtitle)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        
                        Spacer()
                        
                        if viewModel.canLike {
                            Button {
                                HapticService.selection()
                                viewModel.toggleLike()
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: viewModel.isLiked ? "heart.fill" : "heart")
                                        .font(.title2)
                                        .foregroundStyle(viewModel.isLiked ? Color.pink : .white)
                                    
                                    if viewModel.likeCount > 0 {
                                        Text("\(viewModel.likeCount)")
                                            .font(.caption2.bold())
                                            .foregroundStyle(.white.opacity(0.8))
                                    }
                                }
                                .padding(12)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                    
                    // Scrubber
                    HStack(spacing: 12) {
                        Text(timeString(viewModel.progress * viewModel.duration))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.8))
                        
                        ProgressView(value: viewModel.progress)
                            .tint(palette.accent)
                        
                        Text(viewModel.formattedDuration)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    
                    // Playback Controls
                    HStack(spacing: 40) {
                        Button {
                            viewModel.player?.seek(to: .zero)
                        } label: {
                            Image(systemName: "backward.end.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                        }
                        .disabled(viewModel.player == nil)
                        
                        Button {
                            viewModel.togglePlayPause()
                        } label: {
                            Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 56))
                                .foregroundStyle(.white)
                                .shadow(radius: 10)
                        }
                        .disabled(viewModel.player == nil)
                        
                        // Placeholder for next/loop if needed, or just spacer
                        Image(systemName: "forward.end.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.3)) // Disabled look
                    }
                }
                .padding(24)
                .background(
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .mask(LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .bottom, endPoint: .top))
                        .ignoresSafeArea()
                        .padding(.top, -40) // Fade effect
                )
            }
        }
        .onAppear { viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
        .sheet(isPresented: $showingReportSheet) {
            ReportAbuseSheet(
                allowsRelationshipActions: !viewModel.source.isLocal,
                isSubmitting: viewModel.isReporting,
                errorMessage: $viewModel.reportError,
                onSubmit: { reason, note, action in
                    Task {
                        await viewModel.reportVideo(reason: reason, note: note, action: action)
                    }
                },
                onCancel: {
                    showingReportSheet = false
                }
            )
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
    }
    
    @ViewBuilder
    private var videoPlayerArea: some View {
        if let player = viewModel.player {
            VideoPlayer(player: player)
                .aspectRatio(16/9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
        } else {
            // Loading or error state for remote videos
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.1))
                .aspectRatio(16/9, contentMode: .fit)
                .overlay(
                    VStack(spacing: 12) {
                        if let error = viewModel.playbackError {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(.orange)
                            Text(error)
                                .font(.subheadline)
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        } else {
                            ProgressView()
                                .tint(.white)
                            Text("Loading...")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                )
        }
    }
    
    private func timeString(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: seconds) ?? "0:00"
    }
}
