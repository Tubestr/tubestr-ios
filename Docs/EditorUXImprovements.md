# Editor UX Improvements - Implementation Guide

## Overview

This document describes kid-friendly improvements to the MyTube video editor. The goal is to make editing fun, responsive, and delightful for children.

---

## 1. Haptic Feedback Service

### Goal
Add tactile feedback to all interactions so the app feels responsive and "real".

### Implementation

Create `MyTube/Services/HapticService.swift`:

```swift
import UIKit

enum HapticService {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
```

### Integration Points

Add haptic calls in `EditorDetailView.swift`:

| Action | Haptic Type | Location |
|--------|-------------|----------|
| Filter chip tap | `light()` | `FilterChip` button action |
| Sticker selection | `medium()` | `StickerChip` button action |
| Tool tab change | `selection()` | `toolPicker` button action |
| Export success | `success()` | `exportSuccess` onChange handler |
| Validation error | `error()` | When `errorMessage` is set |
| Slider value change | `selection()` | Slider onEditingChanged (throttled) |

---

## 2. Interactive Sticker Positioning

### Goal
Allow kids to drag, resize, and rotate stickers directly on the video preview instead of fixed positioning.

### Data Model Changes

Edit `MyTube/Domain/EditModels.swift`:

```swift
// Add new struct
struct StickerTransform: Codable, Equatable {
    var position: CGPoint = CGPoint(x: 0.5, y: 0.5) // Normalized 0-1
    var scale: CGFloat = 1.0     // Range: 0.5 to 2.0
    var rotation: Double = 0     // Degrees
}
```

### ViewModel Changes

Edit `MyTube/Features/Editor/EditorDetailViewModel.swift`:

```swift
// Add property
@Published var stickerTransform: StickerTransform = StickerTransform()

// Update makeComposition() to use transform values instead of hardcoded frame
func makeComposition() -> EditComposition {
    // ...
    if let sticker = selectedSticker {
        let baseSize: CGFloat = 300
        let scaledSize = baseSize * stickerTransform.scale
        let videoWidth: CGFloat = 1080 // or get from source
        let videoHeight: CGFloat = 1920

        let centerX = stickerTransform.position.x * videoWidth
        let centerY = stickerTransform.position.y * videoHeight

        let stickerFrame = CGRect(
            x: centerX - scaledSize / 2,
            y: centerY - scaledSize / 2,
            width: scaledSize,
            height: scaledSize
        )
        // ... create OverlayItem with frame
    }
}
```

### New View Component

Create `MyTube/Features/Editor/StickerOverlayView.swift`:

```swift
import SwiftUI

struct StickerOverlayView: View {
    let sticker: StickerAsset
    @Binding var transform: StickerTransform
    let containerSize: CGSize

    @State private var dragOffset: CGSize = .zero
    @GestureState private var gestureScale: CGFloat = 1.0
    @GestureState private var gestureRotation: Angle = .zero

    private let baseSize: CGFloat = 100

    var body: some View {
        if let image = ResourceLibrary.stickerImage(named: sticker.id) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: baseSize * transform.scale * gestureScale)
                .rotationEffect(.degrees(transform.rotation) + gestureRotation)
                .position(
                    x: transform.position.x * containerSize.width + dragOffset.width,
                    y: transform.position.y * containerSize.height + dragOffset.height
                )
                .gesture(dragGesture)
                .gesture(magnificationGesture)
                .gesture(rotationGesture)
                .overlay(
                    // Selection border when active
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white, lineWidth: 2)
                        .shadow(radius: 4)
                )
        }
    }

    var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation
                HapticService.selection()
            }
            .onEnded { value in
                // Convert to normalized position
                let newX = transform.position.x + value.translation.width / containerSize.width
                let newY = transform.position.y + value.translation.height / containerSize.height
                transform.position = CGPoint(
                    x: max(0.1, min(0.9, newX)),
                    y: max(0.1, min(0.9, newY))
                )
                dragOffset = .zero
                HapticService.light()
            }
    }

    var magnificationGesture: some Gesture {
        MagnificationGesture()
            .updating($gestureScale) { value, state, _ in
                state = value
            }
            .onEnded { value in
                transform.scale = max(0.5, min(2.0, transform.scale * value))
                HapticService.light()
            }
    }

    var rotationGesture: some Gesture {
        RotationGesture()
            .updating($gestureRotation) { value, state, _ in
                state = value
            }
            .onEnded { value in
                transform.rotation += value.degrees
                HapticService.light()
            }
    }
}
```

### Preview Integration

Edit `EditorDetailView.swift` preview function to overlay the sticker:

```swift
// Inside the ZStack of the video preview, after the VideoPlayer:
if let sticker = viewModel.selectedSticker {
    StickerOverlayView(
        sticker: sticker,
        transform: $viewModel.stickerTransform,
        containerSize: CGSize(width: videoWidth, height: videoHeight)
    )
}
```

---

## 3. Export Celebration

### Goal
Make export completion feel rewarding with confetti animation, sound, and progress feedback.

### Export Step Tracking

Edit `MyTube/Features/Editor/EditorDetailViewModel.swift`:

```swift
enum ExportStep: String, CaseIterable {
    case preparing = "Getting ready..."
    case rendering = "Creating your remix..."
    case scanning = "Safety check..."
    case saving = "Almost done..."
    case complete = "Done!"
}

@Published var exportStep: ExportStep = .preparing

// Update exportEdit() to set steps at appropriate points
func exportEdit() {
    // ...
    exportStep = .preparing

    Task {
        exportStep = .rendering
        // ... VideoLab export

        exportStep = .scanning
        // ... safety scan

        exportStep = .saving
        // ... save to library

        exportStep = .complete
        HapticService.success()
    }
}
```

### Confetti View

Create `MyTube/SharedUI/ConfettiView.swift`:

```swift
import SwiftUI

struct ConfettiParticle: Identifiable {
    let id = UUID()
    var position: CGPoint
    var color: Color
    var rotation: Double
    var scale: CGFloat
    var velocity: CGPoint
}

struct ConfettiView: View {
    @State private var particles: [ConfettiParticle] = []
    @State private var isAnimating = false

    let colors: [Color] = [.red, .blue, .green, .yellow, .orange, .purple, .pink]

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                for particle in particles {
                    let rect = CGRect(
                        x: particle.position.x - 5,
                        y: particle.position.y - 5,
                        width: 10 * particle.scale,
                        height: 10 * particle.scale
                    )
                    context.fill(
                        RoundedRectangle(cornerRadius: 2).path(in: rect),
                        with: .color(particle.color)
                    )
                }
            }
        }
        .onAppear {
            generateParticles()
            startAnimation()
        }
    }

    func generateParticles() {
        particles = (0..<50).map { _ in
            ConfettiParticle(
                position: CGPoint(x: CGFloat.random(in: 0...400), y: -20),
                color: colors.randomElement()!,
                rotation: Double.random(in: 0...360),
                scale: CGFloat.random(in: 0.5...1.5),
                velocity: CGPoint(
                    x: CGFloat.random(in: -2...2),
                    y: CGFloat.random(in: 3...6)
                )
            )
        }
    }

    func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { timer in
            for i in particles.indices {
                particles[i].position.x += particles[i].velocity.x
                particles[i].position.y += particles[i].velocity.y
                particles[i].rotation += 5
            }

            // Stop after particles fall off screen
            if particles.allSatisfy({ $0.position.y > 800 }) {
                timer.invalidate()
            }
        }
    }
}
```

### Enhanced Export Overlay

Edit `EditorDetailView.swift` - replace `scanningOverlay`:

```swift
var exportOverlay: some View {
    let palette = appEnvironment.activeProfile.theme.kidPalette

    return ZStack {
        Color.black.opacity(0.6).ignoresSafeArea()

        VStack(spacing: 24) {
            // Step dots
            HStack(spacing: 16) {
                ForEach(ExportStep.allCases.dropLast(), id: \.self) { step in
                    Circle()
                        .fill(stepReached(step) ? palette.accent : Color.white.opacity(0.3))
                        .frame(width: 12, height: 12)
                        .overlay(
                            stepReached(step) ?
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white) : nil
                        )
                }
            }

            // Current step text
            Text(viewModel.exportStep.rawValue)
                .font(.headline)
                .foregroundStyle(.white)

            if viewModel.exportStep != .complete {
                ProgressView()
                    .tint(palette.accent)
            }

            // Confetti on complete
            if viewModel.exportStep == .complete {
                ConfettiView()
                    .frame(width: 300, height: 400)
            }
        }
        .padding(32)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
    }

    func stepReached(_ step: ExportStep) -> Bool {
        let allSteps = ExportStep.allCases
        guard let currentIndex = allSteps.firstIndex(of: viewModel.exportStep),
              let stepIndex = allSteps.firstIndex(of: step) else { return false }
        return stepIndex <= currentIndex
    }
}
```

---

## 4. Text Customization

### Goal
Let kids customize text with different fonts, colors, sizes, and positions.

### ViewModel Changes

Edit `MyTube/Features/Editor/EditorDetailViewModel.swift`:

```swift
// Add properties
@Published var textFont: String = "Avenir-Heavy"
@Published var textSize: CGFloat = 48
@Published var textColor: Color = .white
@Published var textPosition: TextPosition = .bottom

enum TextPosition: String, CaseIterable {
    case top = "Top"
    case center = "Center"
    case bottom = "Bottom"

    var yOffset: CGFloat {
        switch self {
        case .top: return 100
        case .center: return 400
        case .bottom: return 700
        }
    }
}

static let availableFonts = [
    "Avenir-Heavy",
    "Avenir-Medium",
    "Futura-Bold",
    "Marker Felt",
    "Chalkboard SE"
]

static let textColors: [Color] = [
    .white, .black, .red, .blue, .green, .yellow, .orange, .purple
]

// Update makeComposition() to use these values
if !overlayText.isEmpty {
    overlays.append(
        OverlayItem(
            content: .text(overlayText, fontName: textFont, color: textColor),
            frame: CGRect(x: 120, y: textPosition.yOffset, width: 1040, height: 140),
            start: .zero,
            end: clipDuration
        )
    )
}
```

### Enhanced Text Tool UI

Edit `EditorDetailView.swift` - replace `TextTool`:

```swift
private struct TextTool: View {
    @ObservedObject var viewModel: EditorDetailViewModel
    @EnvironmentObject private var appEnvironment: AppEnvironment

    var body: some View {
        let palette = appEnvironment.activeProfile.theme.kidPalette

        VStack(alignment: .leading, spacing: 20) {
            // Text input
            Text("Caption")
                .font(.subheadline.bold())
                .foregroundStyle(palette.accent)

            TextField("Add text...", text: $viewModel.overlayText, axis: .vertical)
                .lineLimit(3, reservesSpace: true)
                .textFieldStyle(.roundedBorder)
                .foregroundStyle(.black)

            // Font picker
            Text("Font")
                .font(.subheadline.bold())
                .foregroundStyle(palette.accent)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(EditorDetailViewModel.availableFonts, id: \.self) { font in
                        Button {
                            viewModel.textFont = font
                            HapticService.light()
                        } label: {
                            Text("Aa")
                                .font(.custom(font, size: 20))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule().fill(
                                        viewModel.textFont == font ?
                                            palette.accent : Color.white.opacity(0.6)
                                    )
                                )
                                .foregroundStyle(viewModel.textFont == font ? .white : .black)
                        }
                    }
                }
            }

            // Size slider
            HStack {
                Text("Size")
                    .font(.subheadline.bold())
                    .foregroundStyle(palette.accent)
                Slider(value: $viewModel.textSize, in: 24...72)
                    .tint(palette.accent)
                Text("\(Int(viewModel.textSize))")
                    .font(.caption.monospacedDigit())
                    .frame(width: 30)
            }

            // Color picker
            Text("Color")
                .font(.subheadline.bold())
                .foregroundStyle(palette.accent)

            HStack(spacing: 12) {
                ForEach(EditorDetailViewModel.textColors, id: \.self) { color in
                    Button {
                        viewModel.textColor = color
                        HapticService.light()
                    } label: {
                        Circle()
                            .fill(color)
                            .frame(width: 36, height: 36)
                            .overlay(
                                Circle().stroke(Color.white, lineWidth: 2)
                            )
                            .overlay(
                                viewModel.textColor == color ?
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(color == .white ? .black : .white)
                                    : nil
                            )
                    }
                }
            }

            // Position picker
            Text("Position")
                .font(.subheadline.bold())
                .foregroundStyle(palette.accent)

            HStack(spacing: 12) {
                ForEach(TextPosition.allCases, id: \.self) { position in
                    Button {
                        viewModel.textPosition = position
                        HapticService.selection()
                    } label: {
                        Text(position.rawValue)
                            .font(.callout.bold())
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                Capsule().fill(
                                    viewModel.textPosition == position ?
                                        palette.accent : Color.white.opacity(0.6)
                                )
                            )
                            .foregroundStyle(viewModel.textPosition == position ? .white : palette.accent)
                    }
                }
            }

            if !viewModel.overlayText.isEmpty {
                Button("Clear caption") {
                    viewModel.overlayText = ""
                    HapticService.light()
                }
                .buttonStyle(KidSecondaryButtonStyle())
            }
        }
        .padding()
        .kidCardBackground()
    }
}
```

---

## 5. Audio Preview & Volume Control

### Goal
Let kids preview music before selecting and control volume.

### ViewModel Changes

Edit `MyTube/Features/Editor/EditorDetailViewModel.swift`:

```swift
import AVFoundation

// Add properties
@Published var musicVolume: Float = 0.8
@Published var isPreviewingMusic = false
private var previewPlayer: AVAudioPlayer?

func previewMusic(_ track: MusicAsset) {
    stopMusicPreview()

    guard let url = ResourceLibrary.musicURL(for: track.id) else { return }

    do {
        previewPlayer = try AVAudioPlayer(contentsOf: url)
        previewPlayer?.volume = 0.5
        previewPlayer?.play()
        isPreviewingMusic = true
        HapticService.light()

        // Auto-stop after 5 seconds
        Task {
            try? await Task.sleep(for: .seconds(5))
            await MainActor.run {
                stopMusicPreview()
            }
        }
    } catch {
        print("Failed to preview music: \(error)")
    }
}

func stopMusicPreview() {
    previewPlayer?.stop()
    previewPlayer = nil
    isPreviewingMusic = false
}

// Update makeComposition() to use musicVolume
if let music = selectedMusic {
    tracks.append(
        AudioTrack(resourceName: music.id, startOffset: .zero, volume: musicVolume)
    )
}
```

### Enhanced Audio Tool UI

Edit `EditorDetailView.swift` - replace `AudioTool`:

```swift
private struct AudioTool: View {
    @ObservedObject var viewModel: EditorDetailViewModel
    @EnvironmentObject private var appEnvironment: AppEnvironment

    var body: some View {
        let palette = appEnvironment.activeProfile.theme.kidPalette

        VStack(alignment: .leading, spacing: 16) {
            Text("Soundtrack")
                .font(.subheadline.bold())
                .foregroundStyle(palette.accent)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(viewModel.musicTracks) { track in
                        HStack(spacing: 12) {
                            // Preview button
                            Button {
                                if viewModel.isPreviewingMusic {
                                    viewModel.stopMusicPreview()
                                } else {
                                    viewModel.previewMusic(track)
                                }
                            } label: {
                                Image(systemName: viewModel.isPreviewingMusic ? "stop.circle.fill" : "play.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(palette.accent)
                            }

                            // Track info
                            VStack(alignment: .leading, spacing: 4) {
                                Text(track.displayName)
                                    .font(.body.bold())
                                Text("Tap to preview")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            // Selection
                            Button {
                                viewModel.toggleMusic(track)
                                HapticService.medium()
                            } label: {
                                Image(systemName: viewModel.selectedMusic?.id == track.id ?
                                      "checkmark.circle.fill" : "circle")
                                    .font(.title2)
                                    .foregroundStyle(viewModel.selectedMusic?.id == track.id ?
                                                    palette.success : palette.accent)
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(viewModel.selectedMusic?.id == track.id ?
                                      Color.white.opacity(0.9) : Color.white.opacity(0.6))
                        )
                    }
                }
            }
            .frame(maxHeight: 200)

            // Volume control (when track selected)
            if viewModel.selectedMusic != nil {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "speaker.fill")
                        Text("Volume")
                            .font(.subheadline.bold())
                        Spacer()
                        Text("\(Int(viewModel.musicVolume * 100))%")
                            .font(.caption.monospacedDigit())
                    }
                    .foregroundStyle(palette.accent)

                    Slider(value: $viewModel.musicVolume, in: 0...1)
                        .tint(palette.accent)
                }

                Button("Remove music") {
                    viewModel.clearMusic()
                    HapticService.light()
                }
                .buttonStyle(KidSecondaryButtonStyle())
            }
        }
        .padding()
        .kidCardBackground()
        .onDisappear {
            viewModel.stopMusicPreview()
        }
    }
}
```

---

## 6. Thumbnail Scrubber

### Goal
Show visual timeline thumbnails below the playback slider.

### ViewModel Changes

Edit `MyTube/Features/Editor/EditorDetailViewModel.swift`:

```swift
@Published var timelineThumbnails: [UIImage] = []

func generateTimelineThumbnails() async {
    let asset = AVURLAsset(url: sourceURL)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 100, height: 100)

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

// Call in prepare()
func prepare() async {
    // ... existing code ...
    await generateTimelineThumbnails()
}
```

### Enhanced Playback Scrubber

Edit `EditorDetailView.swift` - replace `playbackScrubber`:

```swift
var playbackScrubber: some View {
    VStack(alignment: .leading, spacing: 12) {
        Text("Playback")
            .font(.subheadline.bold())

        // Thumbnail strip
        if !viewModel.timelineThumbnails.isEmpty {
            HStack(spacing: 2) {
                ForEach(viewModel.timelineThumbnails.indices, id: \.self) { index in
                    Image(uiImage: viewModel.timelineThumbnails[index])
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 50)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .cornerRadius(4)
                }
            }
            .cornerRadius(8)
            .overlay(
                // Playhead indicator
                GeometryReader { geo in
                    let progress = playhead / max(viewModel.compositionDuration, 0.01)
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 3)
                        .shadow(radius: 2)
                        .position(x: geo.size.width * progress, y: geo.size.height / 2)
                }
            )
        }

        // Slider
        Slider(
            value: Binding(
                get: { playhead },
                set: { playhead = $0 }
            ),
            in: 0...max(viewModel.compositionDuration, 0.01),
            onEditingChanged: handlePlaybackScrub
        )
        .tint(appEnvironment.activeProfile.theme.kidPalette.accent)

        // Time labels
        HStack {
            Text(timeString(for: playhead))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            Text(timeString(for: viewModel.compositionDuration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
    .padding(.horizontal, 4)
}
```

---

## 7. More Effects

### Goal
Add more video effects: saturation, contrast, pixelate, speed.

### Model Changes

Edit `MyTube/Domain/EditModels.swift`:

```swift
enum VideoEffectKind: String, Codable {
    case zoomBlur
    case brightness
    case saturation   // NEW
    case contrast     // NEW
    case pixelate     // NEW
    // Note: speed requires special handling in composition, skip for now
}
```

### ViewModel Changes

Edit `MyTube/Features/Editor/EditorDetailViewModel.swift`:

```swift
private static let defaultEffectControls: [EffectControl] = [
    EffectControl(id: .zoomBlur, displayName: "Zoom Blur", iconName: "sparkles", range: 0...5, defaultValue: 0),
    EffectControl(id: .brightness, displayName: "Glow", iconName: "sun.max.fill", range: -0.5...0.5, defaultValue: 0),
    EffectControl(id: .saturation, displayName: "Color", iconName: "paintpalette.fill", range: 0...2, defaultValue: 1),
    EffectControl(id: .contrast, displayName: "Contrast", iconName: "circle.lefthalf.filled", range: 0.5...1.5, defaultValue: 1),
    EffectControl(id: .pixelate, displayName: "Pixelate", iconName: "square.grid.3x3.fill", range: 1...50, defaultValue: 1),
]
```

### Renderer Changes

Edit `MyTube/Services/EditRenderer.swift` in `makeVideoLabContext`:

```swift
// In the switch statement for effect.kind:
case .saturation:
    let operation = SaturationAdjustment()
    operation.saturation = effect.intensity
    return operation

case .contrast:
    let operation = ContrastAdjustment()
    operation.contrast = effect.intensity
    return operation

case .pixelate:
    let operation = Pixellate()
    operation.fractionalWidthOfAPixel = effect.intensity / 1000 // Scale appropriately
    return operation
```

Note: Check VideoLab documentation for exact operation class names and parameters.

---

## Implementation Checklist

- [ ] Create `HapticService.swift`
- [ ] Add haptic calls throughout editor
- [ ] Create `StickerOverlayView.swift`
- [ ] Add `StickerTransform` to models
- [ ] Integrate sticker overlay in preview
- [ ] Create `ConfettiView.swift`
- [ ] Add export step tracking
- [ ] Update export overlay UI
- [ ] Add text customization properties to ViewModel
- [ ] Update `TextTool` UI
- [ ] Add music preview to ViewModel
- [ ] Update `AudioTool` UI
- [ ] Add thumbnail generation
- [ ] Update playback scrubber
- [ ] Add new effect types to models
- [ ] Update effect controls
- [ ] Add effect rendering cases

---

## Testing Notes

- Test haptics on real device (simulator doesn't support haptics)
- Test sticker gestures with multi-touch
- Verify confetti animation performance
- Test all font options render correctly
- Verify audio preview stops when leaving tool
- Check thumbnail generation doesn't block UI
- Test new effects render in preview and export
