//
//  PlayerViewModel.swift
//  MyTube
//
//  Created by Codex on 10/24/25.
//

import AVFoundation
import Combine
import Foundation
import OSLog

/// Unified video source for the player - supports both local and remote videos
enum VideoSource {
    case local(RankingEngine.RankedVideo)
    case remote(HomeFeedViewModel.SharedRemoteVideo)
    
    var title: String {
        switch self {
        case .local(let ranked): return ranked.video.title
        case .remote(let shared): return shared.video.title
        }
    }
    
    var duration: TimeInterval {
        switch self {
        case .local(let ranked): return ranked.video.duration
        case .remote(let shared): return shared.video.duration
        }
    }
    
    var createdAt: Date {
        switch self {
        case .local(let ranked): return ranked.video.createdAt
        case .remote(let shared): return shared.video.createdAt
        }
    }
    
    var isLocal: Bool {
        if case .local = self { return true }
        return false
    }
    
    var localVideo: VideoModel? {
        if case .local(let ranked) = self { return ranked.video }
        return nil
    }
    
    var remoteVideo: HomeFeedViewModel.SharedRemoteVideo? {
        if case .remote(let shared) = self { return shared }
        return nil
    }
    
    var videoIdString: String {
        switch self {
        case .local(let ranked): return ranked.video.id.uuidString
        case .remote(let shared): return shared.video.id
        }
    }
    
    var subtitle: String {
        switch self {
        case .local(let ranked):
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: ranked.video.createdAt)
        case .remote(let shared):
            return "Shared by \(shared.ownerDisplayName)"
        }
    }
}

@MainActor
final class PlayerViewModel: ObservableObject {
    @Published private(set) var video: VideoModel?
    @Published private(set) var remoteVideo: HomeFeedViewModel.SharedRemoteVideo?
    @Published private(set) var isPlaying = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var likeCount: Int = 0
    @Published private(set) var likeRecords: [LikeRecord] = []
    @Published var likeError: String?
    @Published var reportError: String?
    @Published var isReporting = false
    @Published var reportSuccess = false
    @Published private(set) var isPublishing = false
    @Published private(set) var playbackError: String?
    @Published private(set) var videoAspectRatio: CGFloat = 16.0 / 9.0

    let source: VideoSource
    var player: AVPlayer? { internalPlayer }

    private let environment: AppEnvironment
    private var internalPlayer: AVPlayer?
    private var timeObserver: Any?
    private var completionObserver: Any?
    private var didCompletePlayback = false
    private let logger = Logger(subsystem: "com.mytube", category: "PlayerViewModel")
    private var viewerPublicKeyHex: String?
    private var viewerChildNpub: String?
    private var viewerDisplayName: String?
    private var cancellables: Set<AnyCancellable> = []
    private var cachedParentKey: String?

    var shouldShowPublishAction: Bool {
        guard let video else { return false }
        return video.approvalStatus == .pending
    }
    
    var title: String { source.title }
    var duration: TimeInterval { source.duration }
    var subtitle: String { source.subtitle }
    var isLiked: Bool { video?.liked ?? false }
    var canLike: Bool { source.isLocal }
    
    /// Returns true if the video can be edited/remixed
    var canEdit: Bool {
        switch source {
        case .local:
            return true
        case .remote(let shared):
            // Can only edit downloaded remote videos
            return shared.video.statusValue == .downloaded && shared.video.localMediaPath != nil
        }
    }
    
    /// Creates a VideoModel suitable for editing. For remote videos, this creates a temporary model.
    func videoModelForEditing() -> VideoModel? {
        switch source {
        case .local(let ranked):
            return ranked.video
        case .remote(let shared):
            guard shared.video.statusValue == .downloaded,
                  let localMediaPath = shared.video.localMediaPath else {
                return nil
            }
            
            // Create a VideoModel from the remote video for editing purposes
            // Use a deterministic UUID based on the remote video ID for consistency
            let editId = UUID(uuidString: shared.video.id) ?? UUID()
            
            return VideoModel(
                id: editId,
                profileId: environment.activeProfile.id,
                filePath: localMediaPath,
                thumbPath: shared.video.localThumbPath ?? "",
                title: "Remix: \(shared.video.title)",
                duration: shared.video.duration,
                createdAt: Date(),
                lastPlayedAt: nil,
                playCount: 0,
                completionRate: 0,
                replayRate: 0,
                liked: false,
                hidden: false,
                tags: [],
                cvLabels: [],
                faceCount: 0,
                loudness: 0,
                reportedAt: nil,
                reportReason: nil,
                approvalStatus: .pending,
                approvedAt: nil,
                approvedByParentKey: nil,
                scanResults: nil,
                scanCompletedAt: nil
            )
        }
    }
    
    var formattedDuration: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = duration >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: duration) ?? "--:--"
    }

    init(source: VideoSource, environment: AppEnvironment) {
        self.source = source
        self.environment = environment

        switch source {
        case .local(let ranked):
            self.video = ranked.video
            let url = environment.videoLibrary.videoFileURL(for: ranked.video)
            self.internalPlayer = AVPlayer(url: url)
            self.videoAspectRatio = Self.computeAspectRatio(for: url)
        case .remote(let shared):
            self.remoteVideo = shared
            // Player will be set up in onAppear after checking file exists
        }

        setupBindings()
    }
    
    /// Convenience initializer for local videos (backwards compatibility)
    convenience init(rankedVideo: RankingEngine.RankedVideo, environment: AppEnvironment) {
        self.init(source: .local(rankedVideo), environment: environment)
    }
    
    /// Convenience initializer for remote videos
    convenience init(remoteVideo: HomeFeedViewModel.SharedRemoteVideo, environment: AppEnvironment) {
        self.init(source: .remote(remoteVideo), environment: environment)
    }

    private func setupBindings() {
        updateViewerIdentity(for: environment.activeProfile)

        environment.likeStore.$likeRecords
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshLikes()
            }
            .store(in: &cancellables)

        environment.$activeProfile
            .sink { [weak self] profile in
                self?.updateViewerIdentity(for: profile)
            }
            .store(in: &cancellables)

        refreshLikes()
    }

    func onAppear() {
        // For remote videos, set up player if not already done
        if case .remote(let shared) = source, internalPlayer == nil {
            prepareRemotePlayer(for: shared)
        }
        attachObservers()
        play()
    }

    func onDisappear() {
        detachObservers()
        
        // Only record playback metrics for local videos
        guard let video, !didCompletePlayback else { return }
        
        Task {
            try? await environment.videoLibrary.recordFeedback(videoId: video.id, action: .skip)
            let update = PlaybackMetricUpdate(
                videoId: video.id,
                playCountDelta: 1,
                completionRate: progress,
                replayRate: video.replayRate,
                liked: nil,
                hidden: nil,
                lastPlayedAt: Date()
            )
            if let updated = try? await environment.videoLibrary.updateMetrics(update) {
                await MainActor.run {
                    self.video = updated
                }
            }
        }
    }
    
    private func prepareRemotePlayer(for shared: HomeFeedViewModel.SharedRemoteVideo) {
        guard let url = shared.video.localMediaURL(root: environment.storagePaths.rootURL) else {
            playbackError = "Video file not found."
            return
        }

        if !FileManager.default.fileExists(atPath: url.path) {
            playbackError = "Video not downloaded."
            return
        }

        videoAspectRatio = Self.computeAspectRatio(for: url)
        let item = AVPlayerItem(url: url)
        internalPlayer = AVPlayer(playerItem: item)
    }

    /// Computes the aspect ratio of a video, accounting for any rotation transform.
    private static func computeAspectRatio(for url: URL) -> CGFloat {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else {
            return 16.0 / 9.0
        }
        let transformed = track.naturalSize.applying(track.preferredTransform)
        let width = abs(transformed.width)
        let height = abs(transformed.height)
        guard height > 0 else { return 16.0 / 9.0 }
        return width / height
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func toggleLike() {
        guard let video else {
            likeError = "Cannot like remote videos."
            return
        }
        guard let viewerKeyHex = viewerPublicKeyHex else {
            likeError = "Set up a child identity before liking videos."
            logger.error("Like toggle requested without child identity.")
            return
        }
        let targetState = !environment.likeStore.hasLiked(videoId: video.id, viewerChildNpub: viewerKeyHex)
        self.video?.liked = targetState
        let viewerNpub = viewerChildNpub ?? viewerKeyHex
        let displayName = viewerDisplayName

        Task {
            do {
                var publishError: Error?
                if targetState {
                    await environment.likeStore.recordLike(
                        videoId: video.id,
                        viewerChildNpub: viewerKeyHex,
                        viewerDisplayName: displayName,
                        isLocalUser: true
                    )
                    do {
                        try await environment.likePublisher.publishLike(
                            videoId: video.id,
                            viewerChildNpub: viewerNpub
                        )
                    } catch {
                        publishError = error
                    }
                    try? await environment.videoLibrary.recordFeedback(videoId: video.id, action: .like)
                } else {
                    await environment.likeStore.removeLike(videoId: video.id, viewerChildNpub: viewerKeyHex)
                    do {
                        try await environment.likePublisher.publishUnlike(
                            videoId: video.id,
                            viewerChildNpub: viewerNpub
                        )
                    } catch {
                        publishError = error
                    }
                    try? await environment.videoLibrary.recordFeedback(videoId: video.id, action: .skip)
                }

                if let error = publishError {
                    if let likeError = error as? LikePublisherError, likeError == .missingVideoOwner {
                        logger.info("Skipping Nostr publish for video \(video.id); owner not found.")
                    } else {
                        throw error
                    }
                }

                let update = PlaybackMetricUpdate(videoId: video.id, liked: targetState)
                if let updated = try? await environment.videoLibrary.updateMetrics(update) {
                    await MainActor.run {
                        self.video = updated
                    }
                }

                await MainActor.run {
                    self.refreshLikes()
                }
            } catch {
                if targetState {
                    await environment.likeStore.removeLike(videoId: video.id, viewerChildNpub: viewerKeyHex)
                } else {
                    await environment.likeStore.recordLike(
                        videoId: video.id,
                        viewerChildNpub: viewerKeyHex,
                        viewerDisplayName: displayName,
                        isLocalUser: true
                    )
                }

                await MainActor.run {
                    self.video?.liked = !targetState
                    self.refreshLikes()
                    self.likeError = error.displayMessage
                }
                logger.error("Failed to toggle like for video \(video.id): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func clearLikeError() {
        likeError = nil
    }

    func publishPendingVideo(pin: String) async throws {
        guard let video, shouldShowPublishAction else { return }
        guard try environment.parentAuth.validate(pin: pin) else {
            throw ParentAuthError.invalidPIN
        }

        let parentKey = cachedParentKey ?? (try? environment.keyStore.fetchKeyPair(role: .parent)?.publicKeyHex.lowercased())
        if cachedParentKey == nil {
            cachedParentKey = parentKey
        }

        isPublishing = true
        defer { isPublishing = false }

        do {
            try await environment.videoShareCoordinator.publishVideo(video.id)
            self.video?.approvalStatus = .approved
            self.video?.approvedAt = Date()
            self.video?.approvedByParentKey = parentKey
        } catch {
            throw error
        }
    }

    func reportVideo(
        reason: ReportReason,
        note: String?,
        action: ReportAction
    ) async {
        guard !isReporting else { return }
        isReporting = true
        reportError = nil
        let subjectChild = reportSubjectChild()
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteValue = (trimmedNote?.isEmpty ?? true) ? nil : trimmedNote

        do {
            _ = try await environment.reportCoordinator.submitReport(
                videoId: source.videoIdString,
                subjectChild: subjectChild,
                reason: reason,
                note: noteValue,
                action: action
            )

            // Only update local video if it's a local source
            if let video {
                if let updated = try? await environment.videoLibrary.markVideoReported(
                    videoId: video.id,
                    reason: reason
                ) {
                    self.video = updated
                }
            }

            reportSuccess = true
        } catch {
            reportError = error.displayMessage
        }

        isReporting = false
    }

    /// Report a video using the child-friendly feeling system
    func reportVideoWithFeeling(
        feeling: ReportFeeling,
        action: ReportAction
    ) async {
        guard !isReporting else { return }
        isReporting = true
        reportError = nil
        let subjectChild = reportSubjectChild()
        let reporterChildId = environment.activeProfile.id.uuidString

        do {
            _ = try await environment.reportCoordinator.submitReport(
                videoId: source.videoIdString,
                subjectChild: subjectChild,
                reason: feeling.reason,
                note: "Child reported feeling: \(feeling.label)",
                level: feeling.level,
                reporterChild: reporterChildId,
                action: action
            )

            // Only update local video if it's a local source
            if let video {
                if let updated = try? await environment.videoLibrary.markVideoReported(
                    videoId: video.id,
                    reason: feeling.reason
                ) {
                    self.video = updated
                }
            }

            reportSuccess = true
        } catch {
            reportError = error.displayMessage
        }

        isReporting = false
    }

    func resetReportState() {
        reportSuccess = false
        reportError = nil
        isReporting = false
    }

    private func play() {
        internalPlayer?.play()
        isPlaying = true
    }

    private func pause() {
        internalPlayer?.pause()
        isPlaying = false
    }

    private func attachObservers() {
        guard let internalPlayer else { return }
        detachObservers()
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        let videoDuration = duration
        timeObserver = internalPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            let currentDuration = self.internalPlayer?.currentItem?.duration.seconds ?? videoDuration
            guard currentDuration > 0 else { return }
            self.progress = min(max(time.seconds / currentDuration, 0), 1)
        }

        completionObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: internalPlayer.currentItem,
            queue: .main
        ) { [weak self] _ in
            self?.handleCompletion()
        }
    }

    private func detachObservers() {
        if let timeObserver, let internalPlayer {
            internalPlayer.removeTimeObserver(timeObserver)
        }
        timeObserver = nil

        if let completionObserver {
            NotificationCenter.default.removeObserver(completionObserver)
        }
        completionObserver = nil
    }

    private func refreshLikes() {
        guard let video else {
            likeRecords = []
            likeCount = 0
            return
        }
        
        let records = environment.likeStore.likes(for: video.id)
        likeRecords = records
        likeCount = records.count

        if let viewerKeyHex = viewerPublicKeyHex {
            let hasLiked = environment.likeStore.hasLiked(videoId: video.id, viewerChildNpub: viewerKeyHex)
            self.video?.liked = hasLiked
        }
    }

    private func updateViewerIdentity(for profile: ProfileModel) {
        do {
            if let identity = try environment.identityManager.childIdentity(for: profile) {
                viewerPublicKeyHex = identity.publicKeyHex.lowercased()
                viewerChildNpub = identity.publicKeyBech32 ?? identity.publicKeyHex.lowercased()
                viewerDisplayName = profile.name
            } else {
                viewerPublicKeyHex = nil
                viewerChildNpub = nil
                viewerDisplayName = profile.name
            }
        } catch {
            viewerPublicKeyHex = nil
            viewerChildNpub = nil
            viewerDisplayName = profile.name
            logger.error("Unable to resolve child identity for profile \(profile.id): \(error.localizedDescription, privacy: .public)")
        }
        refreshLikes()
    }

    private func reportSubjectChild() -> String {
        if let remoteVideo {
            return remoteVideo.video.ownerChild
        }
        return ""
    }

    private func handleCompletion() {
        didCompletePlayback = true
        progress = 1.0
        
        // For remote videos, just loop without tracking metrics
        guard let video else {
            Task { @MainActor in
                self.internalPlayer?.seek(to: .zero)
                self.play()
            }
            return
        }
        
        Task {
            try? await environment.videoLibrary.recordFeedback(videoId: video.id, action: .replay)
            let update = PlaybackMetricUpdate(
                videoId: video.id,
                playCountDelta: 1,
                completionRate: 1.0,
                replayRate: min(1.0, video.replayRate + 0.1),
                liked: nil,
                hidden: nil,
                lastPlayedAt: Date()
            )
            if let updated = try? await environment.videoLibrary.updateMetrics(update) {
                await MainActor.run {
                    self.video = updated
                }
            }
            await MainActor.run {
                self.internalPlayer?.seek(to: .zero)
                self.play()
            }
        }
    }
}
