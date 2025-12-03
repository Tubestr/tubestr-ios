//
//  SelfieStickerCaptureView.swift
//  MyTube
//
//  Created by Claude on 12/3/25.
//

import AVFoundation
import SwiftUI
import UIKit
import VisionKit

/// A view that lets kids take a selfie and use iOS subject lifting to create a sticker
struct SelfieStickerCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: SelfieStickerCaptureViewModel
    let palette: KidPalette
    let onStickerCreated: (StickerAsset) -> Void

    init(
        storagePaths: StoragePaths,
        profileId: UUID,
        palette: KidPalette,
        onStickerCreated: @escaping (StickerAsset) -> Void
    ) {
        _viewModel = StateObject(wrappedValue: SelfieStickerCaptureViewModel(
            storagePaths: storagePaths,
            profileId: profileId
        ))
        self.palette = palette
        self.onStickerCreated = onStickerCreated
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch viewModel.state {
            case .camera:
                cameraView
            case .subjectLifting(let image):
                SubjectLiftingView(
                    image: image,
                    palette: palette,
                    onSubjectExtracted: { extractedImage in
                        viewModel.saveSticker(extractedImage)
                    },
                    onRetake: {
                        viewModel.retakePhoto()
                    }
                )
            case .saving:
                savingView
            case .error(let message):
                errorView(message: message)
            }
        }
        .onAppear { viewModel.startSession() }
        .onDisappear { viewModel.stopSession() }
        .onChange(of: viewModel.createdSticker) { sticker in
            if let sticker {
                onStickerCreated(sticker)
                dismiss()
            }
        }
    }

    private var cameraView: some View {
        ZStack {
            SelfieCameraPreview(session: viewModel.session)
                .ignoresSafeArea()

            VStack {
                // Header with close and flip camera
                HStack {
                    Button {
                        HapticService.light()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.white.opacity(0.9))
                            .shadow(radius: 4)
                    }

                    Spacer()

                    Button {
                        HapticService.light()
                        viewModel.switchCamera()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white.opacity(0.9))
                            .shadow(radius: 4)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)

                Spacer()

                // Instructions
                Text("Take a photo to make a sticker!")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(radius: 4)
                    .padding(.bottom, 16)

                // Capture button
                Button {
                    HapticService.medium()
                    viewModel.capturePhoto()
                } label: {
                    ZStack {
                        Circle()
                            .fill(.white)
                            .frame(width: 80, height: 80)
                        Circle()
                            .stroke(palette.accent, lineWidth: 4)
                            .frame(width: 90, height: 90)
                    }
                }
                .disabled(!viewModel.isSessionReady)
                .opacity(viewModel.isSessionReady ? 1 : 0.5)
                .padding(.bottom, 48)
            }

            if !viewModel.isSessionReady {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
            }
        }
    }

    private var savingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(palette.accent)
            Text("Creating your sticker...")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.yellow)

            Text(message)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Button("Try Again") {
                HapticService.light()
                viewModel.retakePhoto()
            }
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(palette.accent)
            .clipShape(Capsule())
        }
        .padding()
    }
}

// MARK: - Subject Lifting View

/// Uses VisionKit's ImageAnalysisInteraction for the iOS "lift subject" feature
private struct SubjectLiftingView: View {
    let image: UIImage
    let palette: KidPalette
    let onSubjectExtracted: (UIImage) -> Void
    let onRetake: () -> Void

    @State private var extractedSubject: UIImage?
    @State private var isAnalyzing = true
    @State private var analysisError: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button {
                    HapticService.light()
                    onRetake()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.uturn.backward")
                        Text("Retake")
                    }
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                }

                Spacer()

                if extractedSubject != nil {
                    Button {
                        HapticService.success()
                        if let subject = extractedSubject {
                            onSubjectExtracted(subject)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text("Use Sticker")
                            Image(systemName: "checkmark.circle.fill")
                        }
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(palette.accent)
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)

            Spacer()

            // Main content area
            if isAnalyzing {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(palette.accent)
                    Text("Finding you in the photo...")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
            } else if let error = analysisError {
                VStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 48))
                        .foregroundStyle(.yellow)
                    Text(error)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Button("Try Again") {
                        HapticService.light()
                        onRetake()
                    }
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(palette.accent)
                    .clipShape(Capsule())
                }
                .padding()
            } else if let subject = extractedSubject {
                VStack(spacing: 20) {
                    Text("Here's your sticker!")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    // Show the extracted subject with a fun background
                    ZStack {
                        // Checkerboard pattern to show transparency
                        CheckerboardBackground()
                            .frame(width: 280, height: 280)
                            .clipShape(RoundedRectangle(cornerRadius: 20))

                        Image(uiImage: subject)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 260, height: 260)
                    }
                    .shadow(color: .black.opacity(0.3), radius: 10)
                }
            }

            Spacer()

            // Instructions
            if extractedSubject != nil {
                Text("Tap 'Use Sticker' to add it to your video!")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.bottom, 32)
            }
        }
        .task {
            await extractSubject()
        }
    }

    @MainActor
    private func extractSubject() async {
        isAnalyzing = true
        analysisError = nil

        // Check if subject lifting is available
        guard ImageAnalyzer.isSupported else {
            analysisError = "Subject lifting isn't available on this device."
            isAnalyzing = false
            return
        }

        let analyzer = ImageAnalyzer()
        let configuration = ImageAnalyzer.Configuration([.visualLookUp])

        do {
            let analysis = try await analyzer.analyze(image, configuration: configuration)

            // Use ImageAnalysisInteraction to extract subjects
            let interaction = ImageAnalysisInteraction()
            interaction.analysis = analysis
            interaction.preferredInteractionTypes = .imageSubject

            // Check if subjects are available through the interaction
            let subjects = await interaction.subjects
            guard !subjects.isEmpty else {
                analysisError = "Couldn't find anyone in the photo.\nTry taking another picture!"
                isAnalyzing = false
                return
            }

            // Get the subject image through the interaction
            if let subjectImage = try? await interaction.image(for: subjects) {
                extractedSubject = subjectImage
                isAnalyzing = false
                return
            }

            // If we get here, couldn't extract subject
            analysisError = "Couldn't create your sticker.\nTry taking another picture!"
            isAnalyzing = false

        } catch {
            analysisError = "Couldn't create your sticker.\nTry taking another picture!"
            isAnalyzing = false
        }
    }
}

// MARK: - Helper Views

private struct CheckerboardBackground: View {
    let squareSize: CGFloat = 20

    var body: some View {
        Canvas { context, size in
            let rows = Int(size.height / squareSize) + 1
            let cols = Int(size.width / squareSize) + 1

            for row in 0..<rows {
                for col in 0..<cols {
                    let isLight = (row + col) % 2 == 0
                    let rect = CGRect(
                        x: CGFloat(col) * squareSize,
                        y: CGFloat(row) * squareSize,
                        width: squareSize,
                        height: squareSize
                    )
                    context.fill(
                        Path(rect),
                        with: .color(isLight ? Color.gray.opacity(0.3) : Color.gray.opacity(0.5))
                    )
                }
            }
        }
    }
}

private struct SelfieCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> SelfiePreviewView {
        let view = SelfiePreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: SelfiePreviewView, context: Context) {
        uiView.videoPreviewLayer.session = session
        // Handle video mirroring for front camera
        if let connection = uiView.videoPreviewLayer.connection {
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true  // Mirror for selfie view
            }
        }
    }
}

/// Custom UIView subclass that uses AVCaptureVideoPreviewLayer as its backing layer
private final class SelfiePreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

// MARK: - View Model

@MainActor
final class SelfieStickerCaptureViewModel: NSObject, ObservableObject {
    enum State: Equatable {
        case camera
        case subjectLifting(UIImage)
        case saving
        case error(String)

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.camera, .camera), (.saving, .saving):
                return true
            case (.subjectLifting, .subjectLifting):
                return true
            case (.error(let a), .error(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    @Published private(set) var state: State = .camera
    @Published private(set) var isSessionReady = false
    @Published private(set) var createdSticker: StickerAsset?

    let session = AVCaptureSession()
    private let storagePaths: StoragePaths
    private let profileId: UUID

    private var photoOutput: AVCapturePhotoOutput?
    private var currentCameraPosition: AVCaptureDevice.Position = .front

    init(storagePaths: StoragePaths, profileId: UUID) {
        self.storagePaths = storagePaths
        self.profileId = profileId
        super.init()
    }

    func startSession() {
        Task {
            await setupSession()
        }
    }

    func stopSession() {
        session.stopRunning()
    }

    func switchCamera() {
        currentCameraPosition = currentCameraPosition == .front ? .back : .front
        Task {
            await reconfigureCamera()
        }
    }

    func capturePhoto() {
        guard let photoOutput else { return }

        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func retakePhoto() {
        state = .camera
        if !session.isRunning {
            session.startRunning()
        }
    }

    func saveSticker(_ image: UIImage) {
        state = .saving

        Task {
            do {
                let sticker = try ResourceLibrary.saveUserSticker(
                    image: image,
                    storagePaths: storagePaths,
                    profileId: profileId
                )
                createdSticker = sticker
            } catch {
                state = .error("Couldn't save your sticker. Please try again.")
            }
        }
    }

    private func setupSession() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }

        guard status == .authorized || AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            state = .error("Camera access is needed to take selfies")
            return
        }

        session.beginConfiguration()
        session.sessionPreset = .photo

        // Add camera input
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentCameraPosition),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            session.commitConfiguration()
            state = .error("Couldn't access the camera")
            return
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        // Add photo output
        let output = AVCapturePhotoOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            photoOutput = output
        }

        session.commitConfiguration()
        session.startRunning()

        isSessionReady = true
    }

    private func reconfigureCamera() async {
        session.beginConfiguration()

        // Remove existing video input
        for input in session.inputs {
            if let deviceInput = input as? AVCaptureDeviceInput,
               deviceInput.device.hasMediaType(.video) {
                session.removeInput(deviceInput)
            }
        }

        // Add new camera
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentCameraPosition),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            session.commitConfiguration()
            return
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        session.commitConfiguration()
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension SelfieStickerCaptureViewModel: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        Task { @MainActor in
            if let error {
                state = .error("Couldn't take photo: \(error.localizedDescription)")
                return
            }

            guard let data = photo.fileDataRepresentation(),
                  let image = UIImage(data: data) else {
                state = .error("Couldn't process the photo")
                return
            }

            // Correct orientation for front camera (mirror it)
            let correctedImage: UIImage
            if currentCameraPosition == .front {
                correctedImage = image.withHorizontallyFlippedOrientation()
            } else {
                correctedImage = image
            }

            session.stopRunning()
            state = .subjectLifting(correctedImage)
        }
    }
}
