//
//  StickerOverlayView.swift
//  MyTube
//
//  Created for EditorUXImprovements - Interactive Sticker Positioning
//

import SwiftUI

/// An interactive sticker overlay that allows kids to drag, resize, and rotate
/// stickers directly on the video preview.
struct StickerOverlayView: View {
    let sticker: StickerAsset
    @Binding var transform: StickerTransform
    let containerSize: CGSize

    @State private var dragOffset: CGSize = .zero
    @GestureState private var gestureScale: CGFloat = 1.0
    @GestureState private var gestureRotation: Angle = .zero

    private let baseSize: CGFloat = 100

    var body: some View {
        if let image = ResourceLibrary.stickerImage(for: sticker) {
            let currentScale = transform.scale * gestureScale
            let currentRotation = Angle(degrees: transform.rotation) + gestureRotation

            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: baseSize * currentScale, height: baseSize * currentScale)
                .rotationEffect(currentRotation)
                .position(
                    x: transform.position.x * containerSize.width + dragOffset.width,
                    y: transform.position.y * containerSize.height + dragOffset.height
                )
                .overlay(
                    // Selection handles
                    selectionBorder(size: baseSize * currentScale, rotation: currentRotation)
                )
                .gesture(dragGesture)
                .simultaneousGesture(magnificationGesture)
                .simultaneousGesture(rotationGesture)
        }
    }

    @ViewBuilder
    private func selectionBorder(size: CGFloat, rotation: Angle) -> some View {
        let handleSize: CGFloat = 12
        ZStack {
            // Border
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white, lineWidth: 2)
                .frame(width: size + 8, height: size + 8)
                .shadow(color: .black.opacity(0.3), radius: 4)

            // Corner handles
            ForEach(0..<4, id: \.self) { corner in
                Circle()
                    .fill(Color.white)
                    .frame(width: handleSize, height: handleSize)
                    .shadow(color: .black.opacity(0.3), radius: 2)
                    .offset(
                        x: (corner % 2 == 0 ? -1 : 1) * (size / 2 + 2),
                        y: (corner < 2 ? -1 : 1) * (size / 2 + 2)
                    )
            }
        }
        .rotationEffect(rotation)
        .position(
            x: transform.position.x * containerSize.width + dragOffset.width,
            y: transform.position.y * containerSize.height + dragOffset.height
        )
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation
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

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .updating($gestureScale) { value, state, _ in
                state = value
            }
            .onEnded { value in
                transform.scale = max(0.5, min(2.0, transform.scale * value))
                HapticService.light()
            }
    }

    private var rotationGesture: some Gesture {
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

