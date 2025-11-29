//
//  EditorDetailViewModel.swift
//  MyTube
//
//  Created by Codex on 10/24/25.
//

import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import SwiftUI
import UIKit

@MainActor
final class EditorDetailViewModel: ObservableObject {
    enum Tool: CaseIterable {
        case trim
        case effects
        case overlays
        case audio
        case text
    }


    struct EffectControl: Identifiable {
        let id: VideoEffectKind
        let displayName: String
        let iconName: String
        let range: ClosedRange<Float>
        let defaultValue: Float

        var normalizedRange: ClosedRange<Double> {
            Double(range.lowerBound)...Double(range.upperBound)
        }
    }

    private static let defaultEffectControls: [EffectControl] = [
        EffectControl(
            id: .zoomBlur,
            displayName: "Zoom Blur",
            iconName: "sparkles",
            range: 0...5,
            defaultValue: 0
        ),
        EffectControl(
            id: .brightness,
            displayName: "Glow",
            iconName: "sun.max.fill",
            range: -0.5...0.5,
            defaultValue: 0
        ),
        EffectControl(
            id: .saturation,
            displayName: "Color",
            iconName: "paintpalette.fill",
            range: 0...2,
            defaultValue: 1
        ),
        EffectControl(
            id: .contrast,
            displayName: "Contrast",
            iconName: "circle.lefthalf.filled",
            range: 0.5...1.5,
            defaultValue: 1
        ),
        EffectControl(
            id: .pixelate,
            displayName: "Pixelate",
            iconName: "square.grid.3x3.fill",
            range: 1...50,
            defaultValue: 1
        )
    ]

    @Published private(set) var activeTool: Tool = .trim
    @Published private(set) var startTime: Double
    @Published private(set) var endTime: Double
    @Published private(set) var trimmedDuration: Double
    @Published private(set) var selectedSticker: StickerAsset?
    @Published var stickerTransform: StickerTransform = StickerTransform()
    @Published private(set) var selectedMusic: MusicAsset?
    @Published var musicVolume: Float = 0.8
    @Published private(set) var isPreviewingMusic = false
    @Published private(set) var previewingTrackId: String?
    private var previewPlayer: AVAudioPlayer?
    @Published var overlayText: String = "" {
        didSet {
            guard hasPrepared else { return }
            schedulePreviewRebuild(delay: 250_000_000)
        }
    }
    @Published var textFont: String = "Avenir-Heavy" {
        didSet {
            guard hasPrepared else { return }
            schedulePreviewRebuild()
        }
    }
    @Published var textSize: CGFloat = 48 {
        didSet {
            guard hasPrepared else { return }
            schedulePreviewRebuild()
        }
    }
    @Published var textColor: Color = .white {
        didSet {
            guard hasPrepared else { return }
            schedulePreviewRebuild()
        }
    }
    @Published var textPosition: TextPosition = .bottom {
        didSet {
            guard hasPrepared else { return }
            schedulePreviewRebuild()
        }
    }

    /// Text position presets for kid-friendly placement
    enum TextPosition: String, CaseIterable {
        case top = "Top"
        case center = "Center"
        case bottom = "Bottom"

        /// Relative Y offset (0.0 = top, 1.0 = bottom) for positioning text
        var relativeYOffset: CGFloat {
            switch self {
            case .top: return 0.078
            case .center: return 0.5
            case .bottom: return 0.885
            }
        }
    }

    /// Kid-friendly fonts that render well on video
    static let availableFonts = [
        "Avenir-Heavy",
        "Avenir-Medium",
        "Futura-Bold",
        "Marker Felt",
        "Chalkboard SE"
    ]

    /// Bright, fun colors for text overlays
    static let textColors: [Color] = [
        .white, .black, .red, .blue, .green, .yellow, .orange, .purple
    ]
    @Published var selectedFilterID: String? {
        didSet {
            guard hasPrepared else { return }
            schedulePreviewRebuild()
        }
    }
    @Published private(set) var isExporting = false
    @Published private(set) var exportSuccess = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var isDeleting = false
    @Published private(set) var deleteSuccess = false
    @Published private(set) var filters: [FilterDescriptor] = []
    @Published private(set) var stickers: [StickerAsset] = []
    @Published private(set) var musicTracks: [MusicAsset] = []
    @Published private(set) var effectControls: [EffectControl]
    @Published private(set) var isReady = false
    @Published private(set) var previewPlayerItem: AVPlayerItem?
    @Published private(set) var isPreviewLoading = false
    @Published private(set) var compositionDuration: Double = 0
    @Published private(set) var sourceAspectRatio: CGFloat = 9.0 / 16.0
    @Published private(set) var sourceVideoWidth: CGFloat = 1080
    @Published private(set) var sourceVideoHeight: CGFloat = 1920
    @Published private(set) var timelineThumbnails: [UIImage] = []
    @Published private var effectValues: [VideoEffectKind: Float]
    @Published var isScanning = false
    @Published var scanProgress: String?
    @Published private(set) var publishStep: PublishStep = .preparing

    let video: VideoModel

    private let environment: AppEnvironment
    private let sourceURL: URL
    private var hasPrepared = false
    private var previewRefreshTask: Task<Void, Never>?
    private let minimumClipLength: Double = 2.0

    init(video: VideoModel, environment: AppEnvironment) {
        self.video = video
        self.environment = environment
        self.sourceURL = environment.videoLibrary.videoFileURL(for: video)
        self.startTime = 0
        self.endTime = video.duration
        self.trimmedDuration = video.duration
        self.selectedFilterID = nil
        self.effectControls = Self.defaultEffectControls
        self.effectValues = Dictionary(
            uniqueKeysWithValues: Self.defaultEffectControls.map { ($0.id, $0.defaultValue) }
        )

        if !FileManager.default.fileExists(atPath: sourceURL.path) {
            self.errorMessage = "Original video file is missing."
        }

        Task { await prepare() }
    }

    func prepare() async {
        guard !hasPrepared else { return }
        hasPrepared = true
        isReady = false
        await Task.yield()

        filters = FilterPipeline.presets() + FilterPipeline.lutPresets()
        stickers = ResourceLibrary.stickers()
        musicTracks = ResourceLibrary.musicTracks()
        updateSourceAspectRatio()
        trimmedDuration = endTime - startTime
        compositionDuration = trimmedDuration
        isReady = true

        // Generate timeline thumbnails in background
        Task.detached { [weak self] in
            await self?.generateTimelineThumbnails()
        }

        await rebuildPreview()
    }

    /// Generate thumbnail strip for the timeline scrubber
    private func generateTimelineThumbnails() async {
        let asset = AVURLAsset(url: sourceURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 120, height: 120)

        let duration = video.duration
        let count = 8
        var thumbnails: [UIImage] = []

        for i in 0..<count {
            let time = CMTime(seconds: duration * Double(i) / Double(count), preferredTimescale: 600)
            do {
                let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
                thumbnails.append(UIImage(cgImage: cgImage))
            } catch {
                // Skip failed frames
            }
        }

        await MainActor.run {
            self.timelineThumbnails = thumbnails
        }
    }

    func setActiveTool(_ tool: Tool) {
        guard activeTool != tool else { return }
        activeTool = tool
    }

    func updateStartTime(_ value: Double) {
        let clamped = max(0, min(value, endTime - minimumClipLength))
        guard abs(clamped - startTime) > .ulpOfOne else { return }
        startTime = clamped
        trimmedDuration = endTime - startTime
        compositionDuration = trimmedDuration
        schedulePreviewRebuild()
    }

    func updateEndTime(_ value: Double) {
        let clamped = min(max(value, startTime + minimumClipLength), video.duration)
        guard abs(clamped - endTime) > .ulpOfOne else { return }
        endTime = clamped
        trimmedDuration = endTime - startTime
        compositionDuration = trimmedDuration
        schedulePreviewRebuild()
    }

    func toggleSticker(_ sticker: StickerAsset) {
        if selectedSticker?.id == sticker.id {
            selectedSticker = nil
        } else {
            selectedSticker = sticker
            // Reset transform when selecting a new sticker
            stickerTransform = StickerTransform()
        }
        schedulePreviewRebuild()
    }

    func clearSticker() {
        guard selectedSticker != nil else { return }
        selectedSticker = nil
        stickerTransform = StickerTransform()
        schedulePreviewRebuild()
    }

    func toggleMusic(_ track: MusicAsset) {
        if selectedMusic?.id == track.id {
            selectedMusic = nil
        } else {
            selectedMusic = track
        }
        schedulePreviewRebuild()
    }

    func clearMusic() {
        guard selectedMusic != nil else { return }
        stopMusicPreview()
        selectedMusic = nil
        schedulePreviewRebuild()
    }

    /// Preview a music track before selecting it
    func previewMusic(_ track: MusicAsset) {
        stopMusicPreview()

        guard let url = ResourceLibrary.musicURL(for: track.id) else { return }

        do {
            previewPlayer = try AVAudioPlayer(contentsOf: url)
            previewPlayer?.volume = 0.5
            previewPlayer?.play()
            isPreviewingMusic = true
            previewingTrackId = track.id
            HapticService.light()

            // Auto-stop after 5 seconds preview
            Task {
                try? await Task.sleep(for: .seconds(5))
                await MainActor.run {
                    if previewingTrackId == track.id {
                        stopMusicPreview()
                    }
                }
            }
        } catch {
            print("Failed to preview music: \(error)")
        }
    }

    /// Stop any currently playing music preview
    func stopMusicPreview() {
        previewPlayer?.stop()
        previewPlayer = nil
        isPreviewingMusic = false
        previewingTrackId = nil
    }

    func effectValue(for kind: VideoEffectKind) -> Float {
        effectValues[kind] ?? effectControls.first(where: { $0.id == kind })?.defaultValue ?? 0
    }

    func setEffect(_ kind: VideoEffectKind, value: Float) {
        guard let control = effectControls.first(where: { $0.id == kind }) else { return }
        let clamped = min(max(value, control.range.lowerBound), control.range.upperBound)
        guard effectValues[kind] != clamped else { return }
        effectValues[kind] = clamped
        schedulePreviewRebuild()
    }

    func resetEffect(_ kind: VideoEffectKind) {
        guard let control = effectControls.first(where: { $0.id == kind }) else { return }
        effectValues[kind] = control.defaultValue
        schedulePreviewRebuild()
    }

    func binding(for control: EffectControl) -> Binding<Double> {
        Binding(
            get: { Double(self.effectValue(for: control.id)) },
            set: { [weak self] newValue in
                self?.setEffect(control.id, value: Float(newValue))
            }
        )
    }

    func resetEdit() {
        updateStartTime(0)
        updateEndTime(video.duration)
        selectedFilterID = nil
        overlayText = ""
        selectedSticker = nil
        selectedMusic = nil
        effectControls.forEach { control in
            effectValues[control.id] = control.defaultValue
        }
        schedulePreviewRebuild(delay: 0)
    }

    func requestExport() {
        guard !isExporting else { return }
        exportEdit()
    }

    func exportEdit() {
        guard !isExporting else { return }
        guard trimmedDuration >= minimumClipLength else {
            errorMessage = "Clip must be at least \(Int(minimumClipLength)) seconds."
            return
        }

        isExporting = true
        errorMessage = nil
        publishStep = .preparing

        Task {
            isScanning = true
            scanProgress = "Preparing scan…"
            defer {
                isExporting = false
                isScanning = false
                scanProgress = nil
            }
            do {
                publishStep = .processing
                let composition = makeComposition()
                let profileId = environment.activeProfile.id
                let screenScale = await MainActor.run { UIScreen.main.scale }
                let exportedURL = try await environment.editRenderer.exportEdit(
                    composition,
                    profileId: profileId,
                    screenScale: screenScale
                )

                publishStep = .scanning
                let thumbnailURL = try await environment.thumbnailer.generateThumbnail(
                    for: exportedURL,
                    profileId: profileId
                )

                publishStep = .saving
                let request = VideoCreationRequest(
                    profileId: profileId,
                    sourceURL: exportedURL,
                    thumbnailURL: thumbnailURL,
                    title: video.title + " Remix",
                    duration: trimmedDuration,
                    tags: video.tags,
                    cvLabels: video.cvLabels,
                    faceCount: video.faceCount,
                    loudness: video.loudness
                )

                _ = try await environment.videoLibrary.createVideo(request: request) { [weak self] progress in
                    Task { @MainActor in
                        self?.scanProgress = progress
                    }
                }
                try? FileManager.default.removeItem(at: exportedURL)
                try? FileManager.default.removeItem(at: thumbnailURL)

                publishStep = .complete
                HapticService.success()
                
                // Celebration delay for confetti
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                
                exportSuccess = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func acknowledgeExport() {
        exportSuccess = false
    }

    func deleteVideo() {
        guard !isDeleting else { return }
        isDeleting = true
        errorMessage = nil

        Task {
            do {
                try await environment.videoLibrary.deleteVideo(videoId: video.id)
                deleteSuccess = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isDeleting = false
        }
    }

    func rebuildPreviewImmediately() {
        previewRefreshTask?.cancel()
        previewRefreshTask = Task {
            await rebuildPreview()
        }
    }

    func makeComposition() -> EditComposition {
        let clip = ClipSegment(
            sourceURL: sourceURL,
            start: CMTime(seconds: startTime, preferredTimescale: 600),
            end: CMTime(seconds: endTime, preferredTimescale: 600)
        )
        let clipDuration = CMTimeSubtract(clip.end, clip.start)

        var overlays: [OverlayItem] = []
        if let sticker = selectedSticker {
            // Use transform values to calculate sticker frame using actual video dimensions
            let videoWidth = sourceVideoWidth
            let videoHeight = sourceVideoHeight
            // Base sticker size scales with the smaller dimension
            let baseSize: CGFloat = min(videoWidth, videoHeight) * 0.28
            let scaledSize = baseSize * stickerTransform.scale

            let centerX = stickerTransform.position.x * videoWidth
            let centerY = stickerTransform.position.y * videoHeight

            let stickerFrame = CGRect(
                x: centerX - scaledSize / 2,
                y: centerY - scaledSize / 2,
                width: scaledSize,
                height: scaledSize
            )
            overlays.append(
                OverlayItem(
                    content: .sticker(name: sticker.id),
                    frame: stickerFrame,
                    start: .zero,
                    end: clipDuration
                )
            )
        }

        if !overlayText.isEmpty {
            // Scale text height based on font size
            let textHeight = textSize * 2.5
            // Calculate text position relative to actual video dimensions
            let textYOffset = textPosition.relativeYOffset * sourceVideoHeight
            let textMargin = sourceVideoWidth * 0.055
            let textWidth = sourceVideoWidth - (textMargin * 2)
            overlays.append(
                OverlayItem(
                    content: .text(overlayText, fontName: textFont, color: textColor),
                    frame: CGRect(x: textMargin, y: textYOffset, width: textWidth, height: textHeight),
                    start: .zero,
                    end: clipDuration
                )
            )
        }

        var tracks: [AudioTrack] = []
        if let music = selectedMusic {
            tracks.append(
                AudioTrack(resourceName: music.id, startOffset: .zero, volume: musicVolume)
            )
        }

        return EditComposition(
            clip: clip,
            overlays: overlays,
            audioTracks: tracks,
            filterName: selectedFilterID,
            videoEffects: buildVideoEffects()
        )
    }

    private func buildVideoEffects() -> [VideoEffect] {
        effectControls.compactMap { control in
            let value = effectValues[control.id] ?? control.defaultValue
            let epsilon: Float = 0.0001
            guard abs(value - control.defaultValue) > epsilon else { return nil }
            switch control.id {
            case .zoomBlur:
                return VideoEffect(
                    kind: .zoomBlur,
                    intensity: value,
                    center: CGPoint(x: 0.5, y: 0.5)
                )
            case .brightness:
                return VideoEffect(
                    kind: .brightness,
                    intensity: value
                )
            case .saturation:
                return VideoEffect(
                    kind: .saturation,
                    intensity: value
                )
            case .contrast:
                return VideoEffect(
                    kind: .contrast,
                    intensity: value
                )
            case .pixelate:
                return VideoEffect(
                    kind: .pixelate,
                    intensity: value
                )
            }
        }
    }

    private func schedulePreviewRebuild(delay: UInt64 = 120_000_000) {
        guard hasPrepared else { return }
        previewRefreshTask?.cancel()
        previewRefreshTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            guard !Task.isCancelled else { return }
            await self?.rebuildPreview()
        }
    }

    private func rebuildPreview() async {
        guard hasPrepared else { return }
        isPreviewLoading = true
        let composition = makeComposition()
        do {
            let screenScale = await MainActor.run { UIScreen.main.scale }
            let item = try await environment.editRenderer.makePreviewPlayerItem(
                for: composition,
                screenScale: screenScale,
                filterName: selectedFilterID
            )
            previewPlayerItem = item
            compositionDuration = composition.clipDuration.seconds
        } catch {
            errorMessage = error.localizedDescription
        }
        isPreviewLoading = false
    }

    private func updateSourceAspectRatio() {
        let asset = AVURLAsset(url: sourceURL)
        if let track = asset.tracks(withMediaType: .video).first {
            let transformed = track.naturalSize.applying(track.preferredTransform)
            let width = max(abs(transformed.width), 1)
            let height = max(abs(transformed.height), 1)
            sourceVideoWidth = CGFloat(width)
            sourceVideoHeight = CGFloat(height)
            sourceAspectRatio = CGFloat(width / height)
        }
    }
}

private extension EditComposition {
    var clipDuration: CMTime {
        CMTimeSubtract(clip.end, clip.start)
    }
}
