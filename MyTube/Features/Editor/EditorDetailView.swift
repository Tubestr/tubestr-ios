//
//  EditorDetailView.swift
//  MyTube
//
//  Created by Codex on 10/24/25.
//

import AVKit
import SwiftUI

struct EditorDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @StateObject private var viewModel: EditorDetailViewModel

    @State private var player = AVPlayer()
    @State private var isPlaying = false
    @State private var wasPlayingBeforeScrub = false
    @State private var playhead: Double = 0
    @State private var timeObserver: Any?
    @State private var showDeleteConfirm = false
    @State private var isScrubbing = false

    init(video: VideoModel, environment: AppEnvironment) {
        _viewModel = StateObject(wrappedValue: EditorDetailViewModel(video: video, environment: environment))
    }

    var body: some View {
        let palette = appEnvironment.activeProfile.theme.kidPalette
        
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // 1. Background
                palette.backgroundGradient.ignoresSafeArea()

                // 2. Main Content
                VStack(spacing: 0) {
                    // Header
                    header
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .zIndex(10)

                    // Middle Area (Preview + Sidebar)
                    HStack(spacing: 0) {
                        // Preview Area
                        previewArea(in: geometry)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()

                        // Right Sidebar
                        sidebarTools
                            .padding(.trailing, 16)
                            .padding(.leading, 8)
                    }

                    // Bottom Tool Area
                    toolPanel
                        .frame(height: 260)
                        .background(colorScheme == .dark ? Color.black.opacity(0.6) : Color.white.opacity(0.6))
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
                }
                
                // 3. Overlays (Toasts, etc)
                if let message = viewModel.errorMessage {
                    errorToast(message)
                }

                // Unified Progress Overlay (handles export & success/confetti)
                // We keep it visible if scanning OR if we just finished (exportSuccess)
                if viewModel.isScanning || viewModel.exportSuccess {
                    PublishProgressOverlay(
                        currentStep: viewModel.exportSuccess ? .complete : viewModel.publishStep,
                        accentColor: palette.accent
                    )
                    .transition(.opacity)
                }
            }
        }
        .tint(palette.accent)
        .onAppear(perform: configurePlayer)
        .onDisappear(perform: teardownPlayer)
        .onChange(of: viewModel.compositionDuration) { duration in
            let maxDuration = max(duration, 0)
            if playhead > maxDuration {
                playhead = maxDuration
            }
        }
        .onReceive(viewModel.$previewPlayerItem.compactMap { $0 }) { item in
            replacePlayerItem(with: item)
        }
        .onChange(of: viewModel.exportSuccess) { success in
            if success {
                // Small delay to ensure the overlay transition is smooth before dismissal
                Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    await MainActor.run {
                        viewModel.acknowledgeExport()
                        dismiss()
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
            handlePlaybackEnd(notification)
        }
        .onChange(of: viewModel.deleteSuccess) { success in
            if success { dismiss() }
        }
        .confirmationDialog(
            "Delete Video",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Video", role: .destructive) {
                showDeleteConfirm = false
                viewModel.deleteVideo()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will remove the video and its edits from MyTube.")
        }
        .onDisappear {
            if viewModel.exportSuccess {
                viewModel.acknowledgeExport()
            }
        }
        .statusBar(hidden: true)
    }
}

// MARK: - Components
extension EditorDetailView {
    
    var header: some View {
        let palette = appEnvironment.activeProfile.theme.kidPalette
        return HStack {
            Button {
                player.pause()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.accent)
                    .frame(width: 44, height: 44)
                    .background(colorScheme == .dark ? Color.white.opacity(0.15) : Color.white.opacity(0.8), in: Circle())
            }
            
            Spacer()
            
            if viewModel.isExporting {
                ProgressView()
                    .tint(palette.accent)
            } else {
                Button {
                    viewModel.requestExport()
                } label: {
                    Text("Export")
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(palette.accent)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                .disabled(!viewModel.isReady || viewModel.isPreviewLoading)
                .opacity((!viewModel.isReady || viewModel.isPreviewLoading) ? 0.5 : 1)
            }
        }
        .frame(height: 50)
    }
    
    func previewArea(in geometry: GeometryProxy) -> some View {
        // Calculate optimal size maintaining aspect ratio within available space
        
        GeometryReader { geo in
            let availableWidth = geo.size.width
            let availableHeight = geo.size.height
            let aspectRatio = max(viewModel.sourceAspectRatio, 0.1)
            
            let heightForWidth = availableWidth / aspectRatio
            let widthForHeight = availableHeight * aspectRatio
            
            let (videoWidth, videoHeight): (CGFloat, CGFloat) = {
                if heightForWidth <= availableHeight {
                    return (availableWidth, heightForWidth)
                } else {
                    return (widthForHeight, availableHeight)
                }
            }()
            
            ZStack {
                // Video Layer
                VideoPlayer(player: player)
                    .frame(width: videoWidth, height: videoHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
                
                // Interactive Overlays
                if let sticker = viewModel.selectedSticker {
                    StickerOverlayView(
                        sticker: sticker,
                        transform: $viewModel.stickerTransform,
                        containerSize: CGSize(width: videoWidth, height: videoHeight)
                    )
                    .frame(width: videoWidth, height: videoHeight)
                }
                
                // Loading / Play State
                if viewModel.isPreviewLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .shadow(radius: 2)
                } else if viewModel.selectedSticker == nil {
                    Button(action: togglePlayback) {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(.white.opacity(0.8))
                            .shadow(color: .black.opacity(0.3), radius: 10)
                    }
                    .opacity(isPlaying ? 0 : 1) // Hide when playing
                }
                
                // Time & Filter Badges
                VStack {
                    Spacer()
                    HStack {
                        Label(timeString(for: playhead), systemImage: "clock")
                            .font(.caption.monospacedDigit())
                            .padding(8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .foregroundStyle(.primary)
                        
                        Spacer()
                        
                        if let filter = viewModel.selectedFilterID {
                            Text(filterDisplayName(for: filter))
                                .font(.caption)
                                .padding(8)
                                .background(.ultraThinMaterial, in: Capsule())
                                .foregroundStyle(.primary)
                        }
                    }
                    .padding(12)
                }
                .frame(width: videoWidth, height: videoHeight)
            }
            .frame(width: availableWidth, height: availableHeight, alignment: .center)
        }
    }
    
    var sidebarTools: some View {
        let palette = appEnvironment.activeProfile.theme.kidPalette
        return VStack(spacing: 24) {
            ForEach(EditorDetailViewModel.Tool.allCases, id: \.self) { tool in
                let isActive = viewModel.activeTool == tool
                Button {
                    HapticService.selection()
                    viewModel.setActiveTool(tool)
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: tool.iconName)
                            .font(.system(size: 20, weight: .medium))
                            .frame(width: 48, height: 48)
                            .background(
                                Circle()
                                    .fill(isActive ? palette.accent : (colorScheme == .dark ? Color.white.opacity(0.2) : Color.white))
                                    .shadow(color: palette.accent.opacity(0.15), radius: 8, y: 4)
                            )
                            .foregroundStyle(isActive ? .white : palette.accent)
                        
                        Text(tool.displayTitle)
                            .font(.caption2.bold())
                            .foregroundStyle(palette.accent)
                            .shadow(color: (colorScheme == .dark ? Color.black : Color.white).opacity(0.5), radius: 2, x: 0, y: 1)
                    }
                }
            }
            Spacer()
            
            // Delete Button at bottom of sidebar
            Button {
                showDeleteConfirm = true
            } label: {
                Image(systemName: "trash.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.red)
                    .frame(width: 48, height: 48)
                    .background(colorScheme == .dark ? Color.white.opacity(0.2) : Color.white, in: Circle())
                    .shadow(color: Color.black.opacity(0.1), radius: 5)
            }
        }
    }
    
    var toolPanel: some View {
        VStack(spacing: 0) {
            switch viewModel.activeTool {
            case .trim:
                TrimTool(
                    start: viewModel.startTime,
                    end: viewModel.endTime,
                    duration: viewModel.video.duration,
                    playhead: $playhead,
                    compositionDuration: viewModel.compositionDuration,
                    thumbnails: viewModel.timelineThumbnails,
                    updateStart: viewModel.updateStartTime,
                    updateEnd: viewModel.updateEndTime,
                    onScrub: handlePlaybackScrub
                )
            case .effects:
                EffectsTool(viewModel: viewModel)
            case .overlays:
                OverlaysTool(viewModel: viewModel)
            case .audio:
                AudioTool(viewModel: viewModel)
            case .text:
                TextTool(viewModel: viewModel)
            }
        }
    }
    
    func errorToast(_ message: String) -> some View {
        VStack {
            Text(message)
                .font(.footnote.bold())
                .foregroundStyle(.white)
                .padding()
                .background(Color.red.opacity(0.9), in: Capsule())
                .padding(.top, 60)
                .shadow(radius: 10)
            Spacer()
        }
        .onAppear { HapticService.error() }
    }
}

// MARK: - Logic
extension EditorDetailView {
    func configurePlayer() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30),
            queue: .main
        ) { time in
            guard !viewModel.isPreviewLoading, !isScrubbing else { return }
            let seconds = max(time.seconds, 0)
            playhead = min(seconds, viewModel.compositionDuration)
        }
    }

    func teardownPlayer() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        player.pause()
    }

    func replacePlayerItem(with item: AVPlayerItem) {
        isPlaying = false
        player.pause()
        player.replaceCurrentItem(with: item)
        player.seek(to: .zero)
        playhead = 0
    }

    func togglePlayback() {
        guard !viewModel.isPreviewLoading else { return }
        if isPlaying {
            player.pause()
        } else {
            if playhead >= viewModel.compositionDuration {
                player.seek(to: .zero)
                playhead = 0
            }
            player.play()
        }
        isPlaying.toggle()
    }

    func handlePlaybackScrub(_ editing: Bool) {
        isScrubbing = editing
        if editing {
            HapticService.selection()
            wasPlayingBeforeScrub = isPlaying
            player.pause()
            isPlaying = false
        } else {
            HapticService.light()
            let time = CMTime(seconds: playhead, preferredTimescale: 600)
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
            if wasPlayingBeforeScrub {
                player.play()
                isPlaying = true
            }
            wasPlayingBeforeScrub = false
        }
    }
    
    func handlePlaybackEnd(_ notification: Notification) {
        guard let item = notification.object as? AVPlayerItem,
              item == player.currentItem else { return }
        player.seek(to: .zero)
        playhead = 0
        if isPlaying {
            player.play()
        }
    }
    
    func cleanup() {
        if viewModel.exportSuccess {
            viewModel.acknowledgeExport()
        }
    }

    func filterDisplayName(for id: String) -> String {
        viewModel.filters.first(where: { $0.id == id })?.displayName ?? "Custom"
    }

    func timeString(for value: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: value) ?? "0:00"
    }
}

// MARK: - Subviews
private struct TrimTool: View {
    let start: Double
    let end: Double
    let duration: Double
    @Binding var playhead: Double
    let compositionDuration: Double
    let thumbnails: [UIImage]
    let updateStart: (Double) -> Void
    let updateEnd: (Double) -> Void
    let onScrub: (Bool) -> Void
    
    @EnvironmentObject private var appEnvironment: AppEnvironment

    private let minimumGap: Double = 2.0
    private var startRange: ClosedRange<Double> { 0...max(end - minimumGap, 0) }
    private var endRange: ClosedRange<Double> { min(start + minimumGap, duration)...duration }

    var body: some View {
        let palette = appEnvironment.activeProfile.theme.kidPalette
        VStack(alignment: .leading, spacing: 20) {
            
            HStack {
                Text("Trim Video")
                    .font(.headline)
                    .foregroundStyle(palette.accent)
                Spacer()
                Text(timeString(compositionDuration))
                    .font(.subheadline.monospacedDigit().bold())
                    .foregroundStyle(palette.accent)
            }
            
            // Scrubber
            VStack(spacing: 8) {
                // Thumbnail Strip
                if !thumbnails.isEmpty {
                    GeometryReader { geo in
                        HStack(spacing: 0) {
                            ForEach(thumbnails.indices, id: \.self) { index in
                                Image(uiImage: thumbnails[index])
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: geo.size.width / CGFloat(thumbnails.count))
                                    .clipped()
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            // Playhead
                            Rectangle()
                                .fill(palette.accent)
                                .frame(width: 3)
                                .shadow(radius: 1)
                                .offset(x: (playhead / max(compositionDuration, 0.1)) * geo.size.width - (geo.size.width / 2))
                        )
                    }
                    .frame(height: 50)
                    .shadow(color: .black.opacity(0.1), radius: 2)
                }
                
                Slider(value: $playhead, in: 0...max(compositionDuration, 0.01), onEditingChanged: onScrub)
                    .tint(palette.accent)
            }
            
            // Trim Sliders
            HStack(spacing: 24) {
                VStack(alignment: .leading) {
                    Text("Start: \(timeString(start))")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Slider(value: Binding(get: { start }, set: updateStart), in: startRange)
                        .tint(palette.accent)
                }
                
                VStack(alignment: .trailing) {
                    Text("End: \(timeString(end))")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Slider(value: Binding(get: { end }, set: updateEnd), in: endRange)
                        .tint(palette.accent)
                }
            }
        }
        .padding(20)
    }
    
    private func timeString(_ value: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: value) ?? "0:00"
    }
}

private struct EffectsTool: View {
    @ObservedObject var viewModel: EditorDetailViewModel
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = appEnvironment.activeProfile.theme.kidPalette
        VStack(alignment: .leading, spacing: 16) {
            
            Text("Effects")
                .font(.headline)
                .foregroundStyle(palette.accent)
                .padding(.horizontal, 20)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    FilterChip(title: "None", isSelected: viewModel.selectedFilterID == nil) {
                        viewModel.selectedFilterID = nil
                    }
                    
                    ForEach(viewModel.filters) { filter in
                        FilterChip(title: filter.displayName, isSelected: viewModel.selectedFilterID == filter.id) {
                            viewModel.selectedFilterID = filter.id
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            
            Divider().padding(.horizontal, 20)
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    ForEach(viewModel.effectControls, id: \.id) { control in
                        HStack {
                            Image(systemName: control.iconName)
                                .frame(width: 24)
                                .foregroundStyle(palette.accent)
                            Text(control.displayName)
                                .font(.subheadline.bold())
                                .foregroundStyle(.primary)
                            Spacer()
                            if abs(viewModel.binding(for: control).wrappedValue - Double(control.defaultValue)) > 0.01 {
                                Button("Reset") { viewModel.resetEffect(control.id) }
                                    .font(.caption)
                                    .foregroundStyle(palette.accent)
                            }
                        }
                        
                        Slider(value: viewModel.binding(for: control), in: control.normalizedRange)
                            .tint(palette.accent)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .padding(.top, 16)
    }
}

private struct OverlaysTool: View {
    @ObservedObject var viewModel: EditorDetailViewModel
    @EnvironmentObject private var appEnvironment: AppEnvironment

    var body: some View {
        let palette = appEnvironment.activeProfile.theme.kidPalette
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Stickers")
                    .font(.headline)
                    .foregroundStyle(palette.accent)
                Spacer()
                if viewModel.selectedSticker != nil {
                    Button("Remove") { viewModel.clearSticker() }
                        .font(.subheadline.bold())
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 20)
            
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 16) {
                    ForEach(viewModel.stickers) { sticker in
                        StickerChip(
                            asset: sticker,
                            isSelected: viewModel.selectedSticker?.id == sticker.id
                        ) {
                            viewModel.toggleSticker(sticker)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .padding(.top, 16)
    }
}

private struct AudioTool: View {
    @ObservedObject var viewModel: EditorDetailViewModel
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = appEnvironment.activeProfile.theme.kidPalette
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Music")
                    .font(.headline)
                    .foregroundStyle(palette.accent)
                Spacer()
                if viewModel.selectedMusic != nil {
                    Button("Remove") { viewModel.clearMusic() }
                        .font(.subheadline.bold())
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 20)
            
            if viewModel.selectedMusic != nil {
                 HStack {
                    Image(systemName: "speaker.wave.2.fill")
                         .foregroundStyle(palette.accent)
                    Slider(value: $viewModel.musicVolume, in: 0...1)
                        .tint(palette.accent)
                }
                .padding(.horizontal, 20)
            }
            
            List {
                ForEach(viewModel.musicTracks) { track in
                    HStack {
                        Button {
                             if viewModel.previewingTrackId == track.id {
                                 viewModel.stopMusicPreview()
                             } else {
                                 viewModel.previewMusic(track)
                             }
                        } label: {
                            Image(systemName: viewModel.previewingTrackId == track.id ? "stop.circle.fill" : "play.circle.fill")
                                .font(.title2)
                                .foregroundStyle(palette.accent)
                        }
                        .buttonStyle(.plain)
                        
                        Text(track.displayName)
                            .font(.body.bold())
                            .foregroundStyle(.primary)
                        
                        Spacer()
                        
                        if viewModel.selectedMusic?.id == track.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(palette.accent)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        HapticService.selection()
                        viewModel.toggleMusic(track)
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .padding(.top, 16)
        .onDisappear {
            viewModel.stopMusicPreview()
        }
    }
}

private struct TextTool: View {
    @ObservedObject var viewModel: EditorDetailViewModel
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = appEnvironment.activeProfile.theme.kidPalette
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Text Overlay")
                         .font(.headline)
                         .foregroundStyle(palette.accent)
                    Spacer()
                    if !viewModel.overlayText.isEmpty {
                        Button("Clear") { viewModel.overlayText = "" }
                            .font(.subheadline.bold())
                            .foregroundStyle(.red)
                    }
                }
                
                TextField("Enter text...", text: $viewModel.overlayText)
                    .textFieldStyle(.roundedBorder)
                    .foregroundStyle(.primary)
                    .submitLabel(.done)
                    .colorScheme(colorScheme)

                // Styles
                VStack(alignment: .leading, spacing: 10) {
                    Text("Font")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(EditorDetailViewModel.availableFonts, id: \.self) { font in
                                Button {
                                    viewModel.textFont = font
                                } label: {
                                    Text("Aa")
                                        .font(.custom(font, size: 18))
                                        .padding(8)
                                        .background(
                                            Circle().fill(viewModel.textFont == font ? palette.accent : (colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.05)))
                                        )
                                        .foregroundStyle(viewModel.textFont == font ? .white : .primary)
                                }
                            }
                        }
                    }
                }
                
                // Colors
                 VStack(alignment: .leading, spacing: 10) {
                    Text("Color")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(EditorDetailViewModel.textColors, id: \.self) { color in
                                Button {
                                    viewModel.textColor = color
                                } label: {
                                    Circle()
                                        .fill(color)
                                        .frame(width: 32, height: 32)
                                        .overlay(
                                            Circle().stroke(Color.gray.opacity(0.3), lineWidth: viewModel.textColor == color ? 3 : 1)
                                        )
                                        .shadow(radius: 1)
                                }
                            }
                        }
                    }
                }
                
                // Position
                 VStack(alignment: .leading, spacing: 10) {
                    Text("Position")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Picker("Position", selection: $viewModel.textPosition) {
                        ForEach(EditorDetailViewModel.TextPosition.allCases, id: \.self) { pos in
                            Text(pos.rawValue).tag(pos)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                // Size
                 VStack(alignment: .leading, spacing: 10) {
                    Text("Size: \(Int(viewModel.textSize))")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Slider(value: $viewModel.textSize, in: 24...96)
                        .tint(palette.accent)
                }
            }
            .padding(20)
        }
    }
}

// MARK: - Helper Components
private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = appEnvironment.activeProfile.theme.kidPalette
        Button(action: action) {
            Text(title)
                .font(.caption.bold())
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? palette.accent : (colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.05)))
                )
                .foregroundStyle(isSelected ? .white : .primary)
        }
    }
}

private struct StickerChip: View {
    let asset: StickerAsset
    let isSelected: Bool
    let action: () -> Void
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = appEnvironment.activeProfile.theme.kidPalette
        Button(action: action) {
            VStack {
                if let image = ResourceLibrary.stickerImage(named: asset.id) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 60, height: 60)
                } else {
                    Image(systemName: "photo")
                        .frame(width: 60, height: 60)
                        .background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? palette.accent.opacity(0.1) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? palette.accent : Color.clear, lineWidth: 2)
                    )
            )
        }
    }
}

private extension EditorDetailViewModel.Tool {
    var displayTitle: String {
        switch self {
        case .trim: return "Trim"
        case .effects: return "FX"
        case .overlays: return "Stickers"
        case .audio: return "Sound"
        case .text: return "Text"
        }
    }

    var iconName: String {
        switch self {
        case .trim: return "scissors"
        case .effects: return "wand.and.stars"
        case .overlays: return "face.smiling"
        case .audio: return "music.note"
        case .text: return "textformat"
        }
    }
}
