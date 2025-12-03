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
    @State private var isToolPanelExpanded = true

    init(video: VideoModel, environment: AppEnvironment) {
        _viewModel = StateObject(wrappedValue: EditorDetailViewModel(video: video, environment: environment))
    }

    var body: some View {
        let palette = appEnvironment.activeProfile.theme.kidPalette

        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // 1. Background with decorations
                ZStack {
                    palette.backgroundGradient
                    OrganicBlobBackground()
                    FloatingDecorations(intensity: .subtle)
                        .opacity(0.4)
                }
                .ignoresSafeArea()

                // 2. Main Content - Using ZStack for overlay effect
                ZStack(alignment: .bottom) {
                    VStack(spacing: 0) {
                        // Header
                        editorHeader(palette: palette)
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                            .zIndex(10)

                        // Middle Area (Preview + Tools)
                        HStack(spacing: 0) {
                            // Preview Area
                            previewArea(palette: palette, geometry: geometry)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()

                            // Right Sidebar with Playful Icons
                            playfulToolSidebar(palette: palette, isExpanded: $isToolPanelExpanded)
                                .padding(.trailing, 16)
                                .padding(.leading, 12)
                        }
                        .padding(.bottom, isToolPanelExpanded ? 180 : 20)
                    }

                    // Bottom Tool Panel - Overlays video preview
                    if isToolPanelExpanded {
                        VStack(spacing: 0) {
                            // Drag handle
                            Capsule()
                                .fill(palette.cardStroke)
                                .frame(width: 40, height: 5)
                                .padding(.top, 10)
                                .padding(.bottom, 6)

                            toolPanel(palette: palette)
                        }
                        .frame(height: 340)
                        .background(
                            RoundedRectangle(cornerRadius: 32, style: .continuous)
                                .fill(palette.cardFill)
                                .background(
                                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                                        .fill(.ultraThinMaterial)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                                        .stroke(palette.cardStroke, lineWidth: 1)
                                )
                        )
                        .shadow(color: palette.accent.opacity(0.15), radius: 30, y: -12)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .gesture(
                            DragGesture()
                                .onEnded { value in
                                    if value.translation.height > 50 {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                            isToolPanelExpanded = false
                                        }
                                    }
                                }
                        )
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isToolPanelExpanded)

                // 3. Overlays
                if let message = viewModel.errorMessage {
                    errorToast(message, palette: palette)
                }

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
            Text("This will remove the video and its edits from Nook.")
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

    func editorHeader(palette: KidPalette) -> some View {
        HStack(spacing: 16) {
            // Close Button
            Button {
                player.pause()
                dismiss()
            } label: {
                ZStack {
                    Circle()
                        .fill(palette.cardFill)
                        .frame(width: 48, height: 48)

                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(palette.accent)
                }
                .shadow(color: palette.accent.opacity(0.1), radius: 8, y: 4)
            }

            // Title
            VStack(alignment: .leading, spacing: 2) {
                Text("Editing")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(viewModel.video.title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            Spacer()

            // Export Button
            if viewModel.isExporting {
                ProgressView()
                    .tint(palette.accent)
            } else {
                Button {
                    viewModel.requestExport()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 18))
                        Text("Save")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [palette.accent, palette.accentSecondary],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .shadow(color: palette.accent.opacity(0.3), radius: 12, y: 6)
                }
                .disabled(!viewModel.isReady || viewModel.isPreviewLoading)
                .opacity((!viewModel.isReady || viewModel.isPreviewLoading) ? 0.5 : 1)
            }
        }
        .frame(height: 56)
    }

    func previewArea(palette: KidPalette, geometry: GeometryProxy) -> some View {
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
                // Ambient glow behind video
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(palette.accent.opacity(0.1))
                    .blur(radius: 30)
                    .frame(width: videoWidth + 40, height: videoHeight + 40)

                // Video Layer
                VideoPlayer(player: player)
                    .frame(width: videoWidth, height: videoHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(palette.cardStroke, lineWidth: 2)
                    )
                    .shadow(color: palette.accent.opacity(0.15), radius: 20, y: 10)

                // Sticker Overlay (Draggable)
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
                    ZStack {
                        Circle()
                            .fill(palette.cardFill)
                            .frame(width: 80, height: 80)

                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(palette.accent)
                            .scaleEffect(1.3)
                    }
                    .shadow(radius: 10)
                } else if viewModel.selectedSticker == nil {
                    Button(action: togglePlayback) {
                        ZStack {
                            Circle()
                                .fill(.black.opacity(0.3))
                                .frame(width: 80, height: 80)
                                .blur(radius: 8)

                            Circle()
                                .fill(palette.accent)
                                .frame(width: 64, height: 64)

                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.white)
                                .offset(x: isPlaying ? 0 : 2)
                        }
                        .shadow(color: palette.accent.opacity(0.4), radius: 12, y: 4)
                    }
                    .opacity(isPlaying ? 0 : 1)
                }

                // Time & Filter Badges
                VStack {
                    Spacer()
                    HStack {
                        // Time badge
                        HStack(spacing: 6) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 12))
                            Text(timeString(for: playhead))
                                .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                        }
                        .foregroundStyle(palette.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())

                        Spacer()

                        // Filter badge
                        if let filter = viewModel.selectedFilterID {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 12))
                                Text(filterDisplayName(for: filter))
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                            }
                            .foregroundStyle(palette.accentSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                        }
                    }
                    .padding(16)
                }
                .frame(width: videoWidth, height: videoHeight)
            }
            .frame(width: availableWidth, height: availableHeight, alignment: .center)
        }
    }

    func playfulToolSidebar(palette: KidPalette, isExpanded: Binding<Bool>) -> some View {
        VStack(spacing: 20) {
            ForEach(EditorDetailViewModel.Tool.allCases, id: \.self) { tool in
                PlayfulToolButton(
                    tool: tool,
                    isActive: viewModel.activeTool == tool && isExpanded.wrappedValue,
                    palette: palette,
                    action: {
                        HapticService.selection()
                        if viewModel.activeTool == tool && isExpanded.wrappedValue {
                            // Tapping active tool closes panel
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                isExpanded.wrappedValue = false
                            }
                        } else {
                            // Tapping different tool or when collapsed opens panel
                            viewModel.setActiveTool(tool)
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                isExpanded.wrappedValue = true
                            }
                        }
                    }
                )
            }

            Spacer()

            // Delete Button
            Button {
                showDeleteConfirm = true
            } label: {
                ZStack {
                    Circle()
                        .fill(palette.error.opacity(0.15))
                        .frame(width: 56, height: 56)

                    Image(systemName: "trash.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(palette.error)
                }
                .shadow(color: palette.error.opacity(0.2), radius: 8, y: 4)
            }
        }
        .padding(.vertical, 16)
    }

    func toolPanel(palette: KidPalette) -> some View {
        VStack(spacing: 0) {
            switch viewModel.activeTool {
            case .trim:
                TrimToolView(
                    start: viewModel.startTime,
                    end: viewModel.endTime,
                    duration: viewModel.video.duration,
                    playhead: $playhead,
                    compositionDuration: viewModel.compositionDuration,
                    thumbnails: viewModel.timelineThumbnails,
                    updateStart: viewModel.updateStartTime,
                    updateEnd: viewModel.updateEndTime,
                    onScrub: handlePlaybackScrub,
                    palette: palette
                )
            case .effects:
                EffectsToolView(viewModel: viewModel, palette: palette)
            case .overlays:
                OverlaysToolView(
                    viewModel: viewModel,
                    palette: palette,
                    storagePaths: appEnvironment.storagePaths,
                    profileId: viewModel.video.profileId
                )
            case .audio:
                AudioToolView(viewModel: viewModel, palette: palette)
            case .text:
                TextToolView(viewModel: viewModel, palette: palette)
            }
        }
    }

    func errorToast(_ message: String, palette: KidPalette) -> some View {
        VStack {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18))
                Text(message)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(palette.error, in: Capsule())
            .shadow(color: palette.error.opacity(0.3), radius: 12, y: 6)
            .padding(.top, 70)

            Spacer()
        }
        .onAppear { HapticService.error() }
    }
}

// MARK: - Playful Tool Button

private struct PlayfulToolButton: View {
    let tool: EditorDetailViewModel.Tool
    let isActive: Bool
    let palette: KidPalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    // Background
                    Circle()
                        .fill(isActive ? palette.accent : palette.cardFill)
                        .frame(width: 56, height: 56)

                    // Active ring
                    if isActive {
                        Circle()
                            .stroke(palette.accentSecondary, lineWidth: 3)
                            .frame(width: 56, height: 56)
                    }

                    // Icon
                    Image(systemName: tool.iconName)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(isActive ? .white : palette.accent)
                }
                .shadow(color: palette.accent.opacity(isActive ? 0.3 : 0.1), radius: isActive ? 12 : 6, y: 4)

                // Label
                Text(tool.displayTitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(isActive ? palette.accent : .secondary)
            }
        }
        .buttonStyle(BouncyButtonStyle(style: .icon))
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

// MARK: - Tool Views

private struct TrimToolView: View {
    let start: Double
    let end: Double
    let duration: Double
    @Binding var playhead: Double
    let compositionDuration: Double
    let thumbnails: [UIImage]
    let updateStart: (Double) -> Void
    let updateEnd: (Double) -> Void
    let onScrub: (Bool) -> Void
    let palette: KidPalette

    private let minimumGap: Double = 2.0
    private var startRange: ClosedRange<Double> { 0...max(end - minimumGap, 0) }
    private var endRange: ClosedRange<Double> { min(start + minimumGap, duration)...duration }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "scissors")
                    .font(.system(size: 18))
                    .foregroundStyle(palette.accent)
                Text("Trim Your Video")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Spacer()
                Text(timeString(compositionDuration))
                    .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(palette.accent.opacity(0.15), in: Capsule())
            }

            // Thumbnail Strip with Playhead
            if !thumbnails.isEmpty {
                GeometryReader { geo in
                    ZStack {
                        HStack(spacing: 0) {
                            ForEach(thumbnails.indices, id: \.self) { index in
                                Image(uiImage: thumbnails[index])
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: geo.size.width / CGFloat(thumbnails.count))
                                    .clipped()
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(palette.cardStroke, lineWidth: 1)
                        )

                        // Playhead
                        Rectangle()
                            .fill(palette.accent)
                            .frame(width: 4)
                            .clipShape(Capsule())
                            .shadow(color: palette.accent.opacity(0.5), radius: 4)
                            .offset(x: (playhead / max(compositionDuration, 0.1)) * geo.size.width - (geo.size.width / 2))
                    }
                }
                .frame(height: 56)
            }

            // Scrubber Slider
            Slider(value: $playhead, in: 0...max(compositionDuration, 0.01), onEditingChanged: onScrub)
                .tint(palette.accent)

            // Trim Range Sliders
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Start: \(timeString(start))", systemImage: "arrow.right.to.line")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Slider(value: Binding(get: { start }, set: updateStart), in: startRange)
                        .tint(palette.accent)
                }

                VStack(alignment: .trailing, spacing: 4) {
                    Label("End: \(timeString(end))", systemImage: "arrow.left.to.line")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
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

private struct EffectsToolView: View {
    @ObservedObject var viewModel: EditorDetailViewModel
    let palette: KidPalette
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 18))
                    .foregroundStyle(palette.accent)
                Text("Magic Effects")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 20)

            // Filter Chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    FilterChipButton(title: "None", isSelected: viewModel.selectedFilterID == nil, palette: palette) {
                        viewModel.selectedFilterID = nil
                    }

                    ForEach(viewModel.filters) { filter in
                        FilterChipButton(title: filter.displayName, isSelected: viewModel.selectedFilterID == filter.id, palette: palette) {
                            viewModel.selectedFilterID = filter.id
                        }
                    }
                }
                .padding(.horizontal, 20)
            }

            Divider().padding(.horizontal, 20)

            // Effect Sliders
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    ForEach(viewModel.effectControls, id: \.id) { control in
                        HStack(spacing: 12) {
                            Image(systemName: control.iconName)
                                .font(.system(size: 16))
                                .foregroundStyle(palette.accent)
                                .frame(width: 24)

                            Text(control.displayName)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)

                            Slider(value: viewModel.binding(for: control), in: control.normalizedRange)
                                .tint(palette.accent)

                            if abs(viewModel.binding(for: control).wrappedValue - Double(control.defaultValue)) > 0.01 {
                                Button("Reset") { viewModel.resetEffect(control.id) }
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(palette.accent)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
        .padding(.top, 16)
    }
}

private struct OverlaysToolView: View {
    @ObservedObject var viewModel: EditorDetailViewModel
    let palette: KidPalette
    let storagePaths: StoragePaths
    let profileId: UUID

    @State private var showSelfieCaptureSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Image(systemName: "face.smiling.inverse")
                    .font(.system(size: 18))
                    .foregroundStyle(palette.accent)
                Text("Fun Stickers")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Spacer()
                if viewModel.selectedSticker != nil {
                    Button("Remove") { viewModel.clearSticker() }
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(palette.error)
                }
            }
            .padding(.horizontal, 20)

            Text("Drag stickers on your video!")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)

            // Sticker Grid
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 14) {
                    // Selfie Sticker Button
                    SelfieStickerCaptureButton(palette: palette) {
                        HapticService.medium()
                        showSelfieCaptureSheet = true
                    }

                    // User stickers (selfie stickers they've created)
                    ForEach(viewModel.userStickers) { sticker in
                        UserStickerChipButton(
                            asset: sticker,
                            isSelected: viewModel.selectedSticker?.id == sticker.id,
                            palette: palette,
                            onSelect: { viewModel.toggleSticker(sticker) },
                            onDelete: { viewModel.deleteUserSticker(sticker) }
                        )
                    }

                    // Built-in stickers
                    ForEach(viewModel.stickers) { sticker in
                        StickerChipButton(
                            asset: sticker,
                            isSelected: viewModel.selectedSticker?.id == sticker.id,
                            palette: palette
                        ) {
                            viewModel.toggleSticker(sticker)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
        .padding(.top, 16)
        .fullScreenCover(isPresented: $showSelfieCaptureSheet) {
            SelfieStickerCaptureView(
                storagePaths: storagePaths,
                profileId: profileId,
                palette: palette
            ) { newSticker in
                viewModel.addUserSticker(newSticker)
            }
        }
    }
}

private struct AudioToolView: View {
    @ObservedObject var viewModel: EditorDetailViewModel
    let palette: KidPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Image(systemName: "music.note.list")
                    .font(.system(size: 18))
                    .foregroundStyle(palette.accent)
                Text("Add Music")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Spacer()
                if viewModel.selectedMusic != nil {
                    Button("Remove") { viewModel.clearMusic() }
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(palette.error)
                }
            }
            .padding(.horizontal, 20)

            // Volume Slider
            if viewModel.selectedMusic != nil {
                HStack(spacing: 12) {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(palette.accent)
                    Slider(value: $viewModel.musicVolume, in: 0...1)
                        .tint(palette.accent)
                }
                .padding(.horizontal, 20)
            }

            // Music List
            List {
                ForEach(viewModel.musicTracks) { track in
                    MusicTrackRow(
                        track: track,
                        isSelected: viewModel.selectedMusic?.id == track.id,
                        isPreviewing: viewModel.previewingTrackId == track.id,
                        palette: palette,
                        onPreview: {
                            if viewModel.previewingTrackId == track.id {
                                viewModel.stopMusicPreview()
                            } else {
                                viewModel.previewMusic(track)
                            }
                        },
                        onSelect: {
                            HapticService.selection()
                            viewModel.toggleMusic(track)
                        }
                    )
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

private struct MusicTrackRow: View {
    let track: MusicAsset
    let isSelected: Bool
    let isPreviewing: Bool
    let palette: KidPalette
    let onPreview: () -> Void
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPreview) {
                ZStack {
                    Circle()
                        .fill(palette.accent.opacity(0.15))
                        .frame(width: 40, height: 40)

                    Image(systemName: isPreviewing ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(palette.accent)
                }
            }
            .buttonStyle(.plain)

            Text(track.displayName)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(palette.accent)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

private struct TextToolView: View {
    @ObservedObject var viewModel: EditorDetailViewModel
    let palette: KidPalette
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Image(systemName: "textformat.abc")
                        .font(.system(size: 18))
                        .foregroundStyle(palette.accent)
                    Text("Add Text")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Spacer()
                    if !viewModel.overlayText.isEmpty {
                        Button("Clear") { viewModel.overlayText = "" }
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(palette.error)
                    }
                }

                // Text Input
                TextField("Type your message...", text: $viewModel.overlayText)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(palette.cardFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(palette.cardStroke, lineWidth: 1)
                    )
                    .submitLabel(.done)

                // Font Selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Font Style")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(EditorDetailViewModel.availableFonts, id: \.self) { font in
                                Button {
                                    viewModel.textFont = font
                                } label: {
                                    Text("Aa")
                                        .font(.custom(font, size: 18))
                                        .frame(width: 44, height: 44)
                                        .background(
                                            Circle().fill(viewModel.textFont == font ? palette.accent : palette.cardFill)
                                        )
                                        .foregroundStyle(viewModel.textFont == font ? .white : .primary)
                                }
                            }
                        }
                    }
                }

                // Color Selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Color")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(EditorDetailViewModel.textColors, id: \.self) { color in
                                Button {
                                    viewModel.textColor = color
                                } label: {
                                    Circle()
                                        .fill(color)
                                        .frame(width: 36, height: 36)
                                        .overlay(
                                            Circle().stroke(viewModel.textColor == color ? palette.accent : Color.clear, lineWidth: 3)
                                        )
                                        .shadow(radius: 2)
                                }
                            }
                        }
                    }
                }

                // Position
                VStack(alignment: .leading, spacing: 8) {
                    Text("Position")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Picker("Position", selection: $viewModel.textPosition) {
                        ForEach(EditorDetailViewModel.TextPosition.allCases, id: \.self) { pos in
                            Text(pos.rawValue).tag(pos)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // Size
                VStack(alignment: .leading, spacing: 8) {
                    Text("Size: \(Int(viewModel.textSize))")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
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

private struct FilterChipButton: View {
    let title: String
    let isSelected: Bool
    let palette: KidPalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(isSelected ? palette.accent : palette.cardFill)
                )
                .foregroundStyle(isSelected ? .white : .primary)
                .overlay(
                    Capsule()
                        .stroke(isSelected ? palette.accent : palette.cardStroke, lineWidth: 1)
                )
        }
    }
}

private struct StickerChipButton: View {
    let asset: StickerAsset
    let isSelected: Bool
    let palette: KidPalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack {
                if let image = ResourceLibrary.stickerImage(named: asset.id) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 56, height: 56)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 24))
                        .frame(width: 56, height: 56)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? palette.accent.opacity(0.15) : palette.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? palette.accent : Color.clear, lineWidth: 2)
            )
            .shadow(color: isSelected ? palette.accent.opacity(0.2) : .clear, radius: 8, y: 4)
        }
    }
}

/// Button to capture a selfie and create a sticker
private struct SelfieStickerCaptureButton: View {
    let palette: KidPalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(palette.accent.opacity(0.15))
                        .frame(width: 56, height: 56)

                    Image(systemName: "camera.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(palette.accent)
                }

                Text("Selfie")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.accent)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(palette.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(palette.accent.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            )
        }
    }
}

/// Button for user-created stickers with delete option
private struct UserStickerChipButton: View {
    let asset: StickerAsset
    let isSelected: Bool
    let palette: KidPalette
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var showDeleteConfirm = false

    var body: some View {
        Button(action: onSelect) {
            VStack {
                if let fileURL = asset.fileURL,
                   let image = UIImage(contentsOfFile: fileURL.path) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 56, height: 56)
                } else {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 24))
                        .frame(width: 56, height: 56)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? palette.accent.opacity(0.15) : palette.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? palette.accent : Color.clear, lineWidth: 2)
            )
            .shadow(color: isSelected ? palette.accent.opacity(0.2) : .clear, radius: 8, y: 4)
        }
        .contextMenu {
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete Sticker", systemImage: "trash")
            }
        }
        .confirmationDialog(
            "Delete this sticker?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                HapticService.error()
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Tool Extensions

private extension EditorDetailViewModel.Tool {
    var displayTitle: String {
        switch self {
        case .trim: return "Trim"
        case .effects: return "Effects"
        case .overlays: return "Stickers"
        case .audio: return "Music"
        case .text: return "Text"
        }
    }

    var iconName: String {
        switch self {
        case .trim: return "scissors"
        case .effects: return "wand.and.stars"
        case .overlays: return "face.smiling.inverse"
        case .audio: return "music.note.list"
        case .text: return "textformat.abc"
        }
    }
}
