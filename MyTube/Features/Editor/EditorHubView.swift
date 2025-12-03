//
//  EditorHubView.swift
//  MyTube
//
//  Created by Codex on 10/24/25.
//

import SwiftUI
import UIKit

struct EditorHubView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: EditorHubViewModel
    @State private var activeSelection: EditorSelection?
    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
        _viewModel = StateObject(wrappedValue: EditorHubViewModel(environment: environment))
    }

    var body: some View {
        let palette = environment.activeProfile.theme.kidPalette

        ScrollView {
            VStack(spacing: 24) {
                // Header
                editorHeader(palette: palette)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                // Content
                if viewModel.videos.isEmpty {
                    emptyStateView(palette: palette)
                        .padding(.horizontal, 24)
                        .padding(.top, 40)
                } else {
                    // Video Grid
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 20),
                            GridItem(.flexible(), spacing: 20)
                        ],
                        spacing: 24
                    ) {
                        ForEach(viewModel.videos, id: \.id) { video in
                            EditorVideoCard(
                                video: video,
                                thumbnail: thumbnail(for: video),
                                palette: palette,
                                onTap: { activeSelection = EditorSelection(video: video) }
                            )
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
            }
        }
        .background(NookAppBackground(showDecorations: true, decorationIntensity: .subtle))
        .standardToolbar(showLogo: false)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: viewModel.loadVideos) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.accent)
                }
            }
        }
        .fullScreenCover(item: $activeSelection, onDismiss: viewModel.loadVideos) { selection in
            EditorDetailView(video: selection.video, environment: environment)
        }
    }

    // MARK: - Header

    private func editorHeader(palette: KidPalette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Edit Studio")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(palette.accent)

                    Text("Add magic to your videos")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Decorative icon
                ZStack {
                    Circle()
                        .fill(palette.accent.opacity(0.15))
                        .frame(width: 56, height: 56)

                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 24))
                        .foregroundStyle(palette.accent)
                }
                .nookGlow(.soft)
            }

            if !viewModel.videos.isEmpty {
                Text("\(viewModel.videos.count) video\(viewModel.videos.count == 1 ? "" : "s") ready to edit")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Empty State

    private func emptyStateView(palette: KidPalette) -> some View {
        VStack(spacing: 24) {
            // Animated illustration
            ZStack {
                Circle()
                    .fill(palette.accent.opacity(0.08))
                    .frame(width: 160, height: 160)

                Circle()
                    .fill(palette.accent.opacity(0.12))
                    .frame(width: 120, height: 120)

                Image(systemName: "video.badge.waveform")
                    .font(.system(size: 48))
                    .foregroundStyle(palette.accent)
            }
            .nookGlow(.medium)

            VStack(spacing: 8) {
                Text("No videos to edit yet")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Capture a video first, then come\nback here to add effects and stickers!")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(48)
        .cozyCard(cornerRadius: 32, elevation: .floating)
    }

    // MARK: - Helpers

    private func thumbnail(for video: VideoModel) -> UIImage? {
        let url = environment.videoLibrary.thumbnailFileURL(for: video)
        return UIImage(contentsOfFile: url.path)
    }
}

// MARK: - Editor Video Card

private struct EditorVideoCard: View {
    let video: VideoModel
    let thumbnail: UIImage?
    let palette: KidPalette
    let onTap: () -> Void

    @State private var isHovered = false

    /// Compute aspect ratio from thumbnail
    private var thumbnailAspect: CGFloat {
        guard let thumbnail else { return 16/9 }
        guard thumbnail.size.height > 0 else { return 16/9 }
        return thumbnail.size.width / thumbnail.size.height
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                // Thumbnail Area
                ZStack {
                    // Background
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(palette.cardFill)

                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "video.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(palette.accent.opacity(0.4))
                        }
                    }

                    // Edit overlay hint
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            ZStack {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 44, height: 44)

                                Image(systemName: "wand.and.stars")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(palette.accent)
                            }
                            .shadow(color: palette.accent.opacity(0.2), radius: 8, y: 4)
                            .padding(12)
                        }
                    }
                }
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(palette.cardStroke, lineWidth: 1)
                )

                // Info Area
                VStack(alignment: .leading, spacing: 6) {
                    Text(video.title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.system(size: 12))
                        Text(formattedDuration)
                            .font(.system(size: 13, weight: .medium, design: .rounded))

                        Spacer()

                        Text(video.createdAt, style: .date)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(palette.cardFill)
                    .background(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(palette.cardStroke, lineWidth: 1)
            )
            .shadow(color: palette.accent.opacity(0.08), radius: 16, y: 8)
        }
        .buttonStyle(BouncyButtonStyle(style: .secondary))
    }

    private var formattedDuration: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = video.duration >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: video.duration) ?? "--:--"
    }
}

private struct EditorSelection: Identifiable {
    let id = UUID()
    let video: VideoModel
}
