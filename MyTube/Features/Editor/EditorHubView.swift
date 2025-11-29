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
        List(viewModel.videos, id: \.id) { video in
            Button {
                activeSelection = EditorSelection(video: video)
            } label: {
                HStack(spacing: 16) {
                    ThumbnailView(image: thumbnail(for: video))
                    VStack(alignment: .leading) {
                        Text(video.title)
                            .font(.headline)
                        Text(video.createdAt, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .scrollContentBackground(.hidden)
        .background(KidAppBackground())
        .standardToolbar(showLogo: false)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: viewModel.loadVideos) {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .fullScreenCover(item: $activeSelection, onDismiss: viewModel.loadVideos) { selection in
            EditorDetailView(video: selection.video, environment: environment)
        }
        .overlay(alignment: .center) {
            if viewModel.videos.isEmpty {
                Text("Capture a video to start editing.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func thumbnail(for video: VideoModel) -> UIImage? {
        let url = environment.videoLibrary.thumbnailFileURL(for: video)
        return UIImage(contentsOfFile: url.path)
    }
}

private struct ThumbnailView: View {
    let image: UIImage?

    /// Check if thumbnail is portrait orientation
    private var isPortrait: Bool {
        guard let image else { return false }
        return image.size.height > image.size.width
    }

    /// Frame width adapts to portrait vs landscape
    private var frameWidth: CGFloat { isPortrait ? 60 : 120 }

    var body: some View {
        ZStack {
            // Background for consistent appearance
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.gray.opacity(0.1))

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "video.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: frameWidth, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
        )
    }
}

private struct EditorSelection: Identifiable {
    let id = UUID()
    let video: VideoModel
}
