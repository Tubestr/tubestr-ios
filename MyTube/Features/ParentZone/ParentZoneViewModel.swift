//
//  ParentZoneViewModel.swift
//  MyTube
//
//  Created by Codex on 10/24/25.
//

import Combine
import CoreData
import Foundation
import MDKBindings
import NostrSDK
import OSLog
import UIKit

struct MarmotDiagnostics: Equatable {
    let groupCount: Int
    let pendingWelcomes: Int

    static let empty = MarmotDiagnostics(groupCount: 0, pendingWelcomes: 0)
}

@MainActor
final class ParentZoneViewModel: ObservableObject {
    struct PendingWelcomeItem: Identifiable, Equatable {
        let welcome: Welcome

        var id: String { welcome.id }
        var groupName: String {
            let name = welcome.groupName.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? "New Group" : name
        }
        var groupDescription: String? {
            let description = welcome.groupDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            return description.isEmpty ? nil : description
        }
        var welcomerKey: String { welcome.welcomer }
        var relayList: [String] { welcome.groupRelays }
        var memberCount: Int { Int(welcome.memberCount) }
        var adminCount: Int { welcome.groupAdminPubkeys.count }

        var relaySummary: String? {
            guard !relayList.isEmpty else { return nil }
            if relayList.count <= 2 {
                return relayList.joined(separator: ", ")
            }
            let prefix = relayList.prefix(2).joined(separator: ", ")
            return "\(prefix) +\(relayList.count - 2) more"
        }
    }

    struct GroupSummary: Equatable {
        let id: String
        let name: String
        let displayName: String
        let description: String
        let state: String
        let memberCount: Int
        let adminCount: Int
        let relayCount: Int
        let lastMessageAt: Date?

        var isActive: Bool {
            state.lowercased() == "active"
        }
    }

    struct RemoteShareStats: Equatable {
        let availableCount: Int
        let revokedCount: Int
        let deletedCount: Int
        let blockedCount: Int
        let lastSharedAt: Date?

        var totalCount: Int {
            availableCount + revokedCount + deletedCount + blockedCount
        }

        var hasAvailableShares: Bool {
            availableCount > 0
        }
    }

    enum ShareFlowError: LocalizedError {
        case parentIdentityMissing
        case childProfileMissing
        case childKeyMissing(name: String)
        case noApprovedFamilies

        var errorDescription: String? {
            switch self {
            case .parentIdentityMissing:
                return "Generate or import the parent key before sending secure shares."
        case .childProfileMissing:
            return "Could not locate the child's profile for this video. Refresh Parent Zone and try again."
        case .childKeyMissing(let name):
            return "Create or import a key for \(name) before sending secure shares."
        case .noApprovedFamilies:
            return "Accept this family's connection invite before sharing videos."
        }
    }
    }

    @Published var isUnlocked = false
    @Published var pinEntry = ""
    @Published var newPin = ""
    @Published var confirmPin = ""
    @Published var errorMessage: String?
    @Published var videos: [VideoModel] = []
    @Published var storageUsage: StorageUsage = .empty
    @Published var relayEndpoints: [RelayDirectory.Endpoint] = []
    @Published var newRelayURL: String = ""
    @Published var relayStatuses: [RelayHealth] = []
    @Published var parentIdentity: ParentIdentity?
    @Published var parentSecretVisible = false
    @Published var parentProfile: ParentProfileModel?
    @Published var childIdentities: [ChildIdentityItem] = []
    @Published var childSecretVisibility: Set<UUID> = []
    @Published private(set) var publishingChildIDs: Set<UUID> = []
    @Published var reports: [ReportModel] = []
    @Published var storageMode: StorageModeSelection = .managed
    @Published var entitlement: CloudEntitlement?
    @Published var isRefreshingEntitlement = false
    @Published var marmotDiagnostics: MarmotDiagnostics = .empty
    @Published var isRefreshingMarmotDiagnostics = false
    @Published var byoEndpoint: String = ""
    @Published var byoBucket: String = ""
    @Published var byoRegion: String = ""
    @Published var byoAccessKey: String = ""
    @Published var byoSecretKey: String = ""
    @Published var byoPathStyle: Bool = true
    @Published var backendEndpoint: String = ""
    @Published private(set) var pendingWelcomes: [PendingWelcomeItem] = []
    @Published var isRefreshingPendingWelcomes = false
    @Published private(set) var welcomeActionsInFlight: Set<String> = []
    @Published private(set) var groupSummaries: [String: GroupSummary] = [:]
    @Published private(set) var shareStatsByChild: [String: RemoteShareStats] = [:]
    @Published var requiresVideoApproval: Bool = false
    @Published var enableContentScanning: Bool = true
    @Published var pendingApprovalVideos: [VideoModel] = []
    @Published var pendingFollowInviteData: String?

    private let environment: AppEnvironment
    private let parentAuth: ParentAuth
    private let parentKeyPackageStore: ParentKeyPackageStore
    private let welcomeClient: any WelcomeHandling
    private let parentalControlsStore: ParentalControlsStore
    private var lastCreatedChildID: UUID?
    private var childKeyLookup: [String: ChildIdentityItem] = [:]
    private var pendingParentKeyPackages: [String: [String]]
    private let eventSigner = NostrEventSigner()

    enum KeyPackageFetchState: Equatable {
        case idle
        case fetching(parentKey: String)
        case fetched(parentKey: String, count: Int)
        case failed(parentKey: String, error: String)
    }
    @Published var keyPackageFetchState: KeyPackageFetchState = .idle
    private var hasPublishedKeyPackage = false
    private var cancellables: Set<AnyCancellable> = []
    private var localParentKeyVariants: Set<String> = []
    private var marmotObservers: [NSObjectProtocol] = []
    private var lifecycleObservers: [NSObjectProtocol] = []
    private let logger = Logger(subsystem: "com.mytube", category: "ParentZoneViewModel")
    
    // Auto-lock configuration
    private static let inactivityLockInterval: TimeInterval = 5 * 60 // 5 minutes
    private static let backgroundLockDelay: TimeInterval = 5 // 5 seconds after backgrounding
    private var inactivityTimer: Timer?
    private var backgroundLockTask: Task<Void, Never>?
    private var lastActivityTime: Date = Date()

    init(environment: AppEnvironment, welcomeClient: (any WelcomeHandling)? = nil) {
        self.environment = environment
        self.parentAuth = environment.parentAuth
        self.parentKeyPackageStore = environment.parentKeyPackageStore
        self.welcomeClient = welcomeClient ?? environment.mdkActor
        self.pendingParentKeyPackages = environment.parentKeyPackageStore.allPackages()
        self.storageMode = environment.storageModeSelection
        self.parentalControlsStore = environment.parentalControlsStore

        loadStoredBYOConfig()
        backendEndpoint = environment.backendEndpointString()

        environment.reportStore.$reports
            .receive(on: RunLoop.main)
            .sink { [weak self] reports in
                self?.reports = reports.sorted { $0.createdAt > $1.createdAt }
            }
            .store(in: &cancellables)

        environment.$storageModeSelection
            .removeDuplicates()
            .sink { [weak self] mode in
                guard let self else { return }
                self.storageMode = mode
                if mode == .byo {
                    self.loadStoredBYOConfig()
                }
            }
            .store(in: &cancellables)

        Publishers.CombineLatest($isUnlocked, environment.$pendingDeepLink)
            .receive(on: RunLoop.main)
            .sink { [weak self] unlocked, deepLink in
                guard let self, unlocked, let deepLink else { return }
                self.handleDeepLink(deepLink)
            }
            .store(in: &cancellables)

        observeMarmotNotifications()
        observeParentProfileChanges()
        observeAppLifecycle()
        loadParentalControls()
    }

    deinit {
        for observer in marmotObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        for observer in lifecycleObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        inactivityTimer?.invalidate()
        backgroundLockTask?.cancel()
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "tubestr" else { return }

        // Clear the pending link so we don't process it again
        environment.pendingDeepLink = nil

        if url.host == "follow-invite" {
            // Pass the full URL string so FollowInvite.decode can parse it correctly via decodeURLString
            self.pendingFollowInviteData = url.absoluteString
        }
    }

    var needsSetup: Bool {
        !parentAuth.isPinConfigured()
    }

    func authenticate() {
        do {
            if parentAuth.isPinConfigured() {
                guard try parentAuth.validate(pin: pinEntry) else {
                    errorMessage = "Incorrect PIN"
                    return
                }
                unlock()
            } else {
                guard newPin == confirmPin, newPin.count >= 4 else {
                    errorMessage = "PINs must match and be 4+ digits"
                    return
                }
                try parentAuth.configure(pin: newPin)
                unlock()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func unlockWithBiometrics() {
        Task {
            do {
                try await parentAuth.evaluateBiometric(reason: "Unlock Parent Zone")
                unlock()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func publishParentProfile(name: String?) async {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedName.isEmpty else {
            errorMessage = "Enter a parent name before publishing."
            return
        }

        do {
            let model = try await environment.parentProfilePublisher.publishProfile(
                name: trimmedName,
                displayName: trimmedName,
                about: nil,
                pictureURL: nil,
                nip05: nil
            )
            parentProfile = model
            if let identity = try environment.identityManager.parentIdentity() {
                parentIdentity = identity
                updateParentKeyCache(identity)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func publishChildProfile(childId: UUID) {
        guard let index = childIdentities.firstIndex(where: { $0.id == childId }) else {
            errorMessage = "Child profile not found."
            return
        }
        let item = childIdentities[index]
        guard let identity = item.identity else {
            errorMessage = "Generate a child key before publishing."
            return
        }

        publishingChildIDs.insert(childId)
        let profile = item.profile

        Task {
            do {
                let metadata = try await environment.childProfilePublisher.publishProfile(
                    for: profile,
                    identity: identity
                )
                await MainActor.run {
                    guard let currentIndex = self.childIdentities.firstIndex(where: { $0.id == childId }) else {
                        return
                    }
                    self.childIdentities[currentIndex] = self.childIdentities[currentIndex].updating(metadata: metadata)
                    if let identity = self.childIdentities[currentIndex].identity {
                        let hex = identity.publicKeyHex.lowercased()
                        self.childKeyLookup[hex] = self.childIdentities[currentIndex]
                        if let bech32 = identity.publicKeyBech32?.lowercased() {
                            self.childKeyLookup[bech32] = self.childIdentities[currentIndex]
                        }
                    }
                    self.errorMessage = nil
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.displayMessage
                }
            }

            await MainActor.run {
                self.publishingChildIDs.remove(childId)
            }
        }
    }

    func refreshVideos() {
        do {
            videos = try environment.videoLibrary.fetchVideos(profileId: environment.activeProfile.id, includeHidden: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadParentalControls() {
        requiresVideoApproval = parentalControlsStore.requiresVideoApproval
        enableContentScanning = parentalControlsStore.enableContentScanning || parentalControlsStore.requiresVideoApproval
    }

    func updateApprovalRequirement(_ enabled: Bool) {
        parentalControlsStore.setRequiresVideoApproval(enabled)
        requiresVideoApproval = enabled
        if enabled {
            enableContentScanning = true
        }
        loadPendingApprovals()
    }

    func updateContentScanning(_ enabled: Bool) {
        guard !requiresVideoApproval else {
            enableContentScanning = true
            parentalControlsStore.setEnableContentScanning(true)
            return
        }
        enableContentScanning = enabled
        parentalControlsStore.setEnableContentScanning(enabled)
    }

    func loadPendingApprovals() {
        let request = VideoEntity.fetchRequest()
        request.predicate = NSPredicate(format: "approvalStatus == %@", VideoModel.ApprovalStatus.pending.rawValue)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \VideoEntity.createdAt, ascending: false)]
        do {
            let entities = try environment.persistence.viewContext.fetch(request)
            pendingApprovalVideos = entities.compactMap(VideoModel.init(entity:))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshPendingApprovals() {
        loadPendingApprovals()
    }

    func approvePendingVideo(_ videoId: UUID) {
        Task {
            do {
                try await environment.videoShareCoordinator.publishVideo(videoId)
                loadPendingApprovals()
            } catch {
                errorMessage = error.displayMessage
            }
        }
    }

    func storageBreakdown() {
        let root = environment.storagePaths.rootURL
        let media = totalSize(at: root.appendingPathComponent(StoragePaths.Directory.media.rawValue))
        let thumbs = totalSize(at: root.appendingPathComponent(StoragePaths.Directory.thumbs.rawValue))
        let edits = totalSize(at: root.appendingPathComponent(StoragePaths.Directory.edits.rawValue))
        storageUsage = StorageUsage(media: media, thumbs: thumbs, edits: edits)
    }

    func refreshEntitlement(force: Bool = false) {
        guard storageMode == .managed else {
            entitlement = nil
            isRefreshingEntitlement = false
            errorMessage = nil
            return
        }
        isRefreshingEntitlement = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isRefreshingEntitlement = false }
            do {
                self.logger.info("Requesting entitlement from \(self.environment.backendEndpointString(), privacy: .public)")
                let response = try await self.environment.backendClient.fetchEntitlement(forceRefresh: force)
                self.entitlement = CloudEntitlement(response: response)
                if self.storageMode == .managed {
                    self.errorMessage = nil
                }
            } catch {
                self.logger.error("Entitlement fetch failed: \(error.localizedDescription, privacy: .public)")
                self.errorMessage = error.displayMessage
            }
        }
    }

    func activateManagedStorage() {
        do {
            try environment.applyStorageMode(.managed)
            storageMode = .managed
            errorMessage = nil
            backendEndpoint = environment.backendEndpointString()
            entitlement = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func activateBYOStorage() {
        guard let config = buildBYOConfigFromInputs() else {
            return
        }
        do {
            try environment.applyStorageMode(.byo, config: config)
            storageMode = .byo
            errorMessage = nil
            loadStoredBYOConfig()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadStoredBYOConfig() {
        guard let config = try? environment.storageConfigurationStore.loadBYOConfig() else {
            resetBYOFormFields()
            return
        }

        byoEndpoint = config.endpoint.absoluteString
        byoBucket = config.bucket
        byoRegion = config.region
        byoAccessKey = config.accessKey
        byoSecretKey = config.secretKey
        byoPathStyle = config.pathStyle
    }

    private func resetBYOFormFields() {
        byoEndpoint = ""
        byoBucket = ""
        byoRegion = ""
        byoAccessKey = ""
        byoSecretKey = ""
        byoPathStyle = true
    }

    private func buildBYOConfigFromInputs() -> UserStorageConfig? {
        let endpointString = byoEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !endpointString.isEmpty else {
            errorMessage = "Enter the S3 endpoint URL."
            return nil
        }

        guard let endpointURL = URL(string: endpointString),
              let scheme = endpointURL.scheme?.lowercased(),
              scheme == "https" || scheme == "http"
        else {
            errorMessage = "Endpoint URL must start with https:// or http://."
            return nil
        }

        let bucket = byoBucket.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bucket.isEmpty else {
            errorMessage = "Enter the bucket name."
            return nil
        }

        let regionValue = byoRegion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !regionValue.isEmpty else {
            errorMessage = "Enter the storage region."
            return nil
        }

        let accessKeyValue = byoAccessKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accessKeyValue.isEmpty else {
            errorMessage = "Enter the access key."
            return nil
        }

        guard !byoSecretKey.isEmpty else {
            errorMessage = "Enter the secret key."
            return nil
        }

        return UserStorageConfig(
            endpoint: endpointURL,
            bucket: bucket,
            region: regionValue,
            accessKey: accessKeyValue,
            secretKey: byoSecretKey,
            pathStyle: byoPathStyle
        )
    }

    func applyBackendEndpoint() {
        let trimmed = backendEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Enter the backend base URL."
            return
        }

        guard storageMode == .managed else {
            errorMessage = "Switch to Managed storage before configuring the MyTube backend."
            return
        }

        guard
            let url = URL(string: trimmed),
            let scheme = url.scheme?.lowercased(),
            ["https", "http"].contains(scheme),
            url.host != nil
        else {
            errorMessage = "Backend URL must include http(s) scheme and host."
            return
        }

        environment.updateBackendEndpoint(url)
        backendEndpoint = url.absoluteString
        entitlement = nil
        errorMessage = nil
    }

    func toggleVisibility(for video: VideoModel) {
        Task {
            do {
                let updated = try await environment.videoLibrary.toggleHidden(videoId: video.id, isHidden: !video.hidden)
                updateCache(with: updated)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func delete(video: VideoModel) {
        Task {
            do {
                try await environment.videoLibrary.deleteVideo(videoId: video.id)
                videos.removeAll { $0.id == video.id }
            } catch {
                errorMessage = error.localizedDescription
            }
            storageBreakdown()
        }
    }

    func shareURL(for video: VideoModel) -> URL {
        environment.videoLibrary.videoFileURL(for: video)
    }

    func canShareRemotely(video: VideoModel) -> Bool {
        guard parentIdentity != nil else { return false }
        guard let item = childIdentities.first(where: { $0.id == video.profileId }),
              item.identity != nil else {
            return false
        }
        return !approvedParentKeys(forChild: video.profileId).isEmpty
    }

    func shareVideoRemotely(video: VideoModel, recipientPublicKey: String) async throws -> VideoShareMessage {
        let parentIdentity: ParentIdentity
        do {
            parentIdentity = try ensureParentIdentityLoaded()
        } catch {
            throw ShareFlowError.parentIdentityMissing
        }

        if !childIdentities.contains(where: { $0.id == video.profileId }) {
            loadIdentities()
        }

        guard let childItem = childIdentities.first(where: { $0.id == video.profileId }) else {
            throw ShareFlowError.childProfileMissing
        }
        guard let identity = childItem.identity else {
            throw ShareFlowError.childKeyMissing(name: childItem.displayName)
        }

        guard let remoteParent = ParentIdentityKey(string: recipientPublicKey) else {
            throw VideoSharePublisherError.invalidRecipientKey
        }

        guard let groupId = identity.profile.primaryGroupId else {
            throw GroupMembershipWorkflowError.groupIdentifierMissing
        }

        let ownerChild = identity.publicKeyBech32 ?? identity.publicKeyHex
        let message = try await environment.videoSharePublisher.makeShareMessage(
            video: video,
            ownerChildNpub: ownerChild
        )
        _ = try await environment.marmotShareService.publishVideoShare(
            message: message,
            mlsGroupId: groupId
        )
        return message
    }

    func ensureRelayConnection(
        timeout: TimeInterval = 5,
        pollInterval: TimeInterval = 0.5
    ) async -> Bool {
        await environment.syncCoordinator.refreshRelays()

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let statuses = await environment.syncCoordinator.relayStatuses()
            if statuses.contains(where: { $0.status == .connected }) {
                return true
            }
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
        return false
    }

    /// Locks the Parent Zone, requiring re-authentication
    func lock() {
        isUnlocked = false
        pinEntry = ""
        errorMessage = nil
        stopAutoLockTimers()
    }
    
    /// Call this when the user interacts with the Parent Zone to reset the inactivity timer
    func recordActivity() {
        guard isUnlocked else { return }
        lastActivityTime = Date()
        restartInactivityTimer()
    }
    
    /// Called when the Parent Zone becomes visible
    func onAppear() {
        if isUnlocked {
            restartInactivityTimer()
        }
        cancelBackgroundLockTask()
    }
    
    /// Called when the Parent Zone is no longer visible (tab switch)
    func onDisappear() {
        stopAutoLockTimers()
        lock()
    }
    
    // MARK: - Auto-lock Implementation
    
    private func observeAppLifecycle() {
        let center = NotificationCenter.default
        
        let backgroundObserver = center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAppDidEnterBackground()
        }
        
        let foregroundObserver = center.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAppWillEnterForeground()
        }
        
        lifecycleObservers.append(contentsOf: [backgroundObserver, foregroundObserver])
    }
    
    private func handleAppDidEnterBackground() {
        guard isUnlocked else { return }
        
        // Stop inactivity timer while in background
        inactivityTimer?.invalidate()
        inactivityTimer = nil
        
        // Schedule lock after background delay
        backgroundLockTask?.cancel()
        backgroundLockTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(Self.backgroundLockDelay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.lock()
                self?.logger.info("Parent Zone locked due to app backgrounding")
            } catch {
                // Task was cancelled, don't lock
            }
        }
    }
    
    private func handleAppWillEnterForeground() {
        cancelBackgroundLockTask()
        
        // Check if we should lock due to inactivity while backgrounded
        if isUnlocked {
            let timeSinceLastActivity = Date().timeIntervalSince(lastActivityTime)
            if timeSinceLastActivity >= Self.inactivityLockInterval {
                lock()
                logger.info("Parent Zone locked due to inactivity while backgrounded")
            } else {
                restartInactivityTimer()
            }
        }
    }
    
    private func cancelBackgroundLockTask() {
        backgroundLockTask?.cancel()
        backgroundLockTask = nil
    }
    
    private func restartInactivityTimer() {
        inactivityTimer?.invalidate()
        
        let remainingTime = Self.inactivityLockInterval - Date().timeIntervalSince(lastActivityTime)
        guard remainingTime > 0 else {
            lock()
            logger.info("Parent Zone locked due to inactivity")
            return
        }
        
        inactivityTimer = Timer.scheduledTimer(withTimeInterval: remainingTime, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.lock()
                self?.logger.info("Parent Zone locked due to inactivity timer")
            }
        }
    }
    
    private func stopAutoLockTimers() {
        inactivityTimer?.invalidate()
        inactivityTimer = nil
        cancelBackgroundLockTask()
    }
    
    private func unlock() {
        isUnlocked = true
        pinEntry = ""
        newPin = ""
        confirmPin = ""
        errorMessage = nil
        
        // Start auto-lock timers
        lastActivityTime = Date()
        restartInactivityTimer()
        
        refreshVideos()
        storageBreakdown()
        loadRelays()
        loadIdentities()
        loadRelationships()
        loadParentalControls()
        loadPendingApprovals()
        loadStoredBYOConfig()
        refreshEntitlement()
        refreshMarmotDiagnostics()
        refreshGroupSummaries()
        refreshRemoteShareStats()
        publishKeyPackageIfNeeded()
        Task {
            await linkOrphanedGroups()
            await refreshPendingWelcomes()
            refreshPendingApprovals()
            await environment.syncCoordinator.refreshSubscriptions()
        }
    }
    
    private func linkOrphanedGroups() async {
        
        // Get all groups from MDK
        let groups: [Group]
        do {
            groups = try await environment.mdkActor.getGroups()
        } catch {
            return
        }
        
        // Get all child profiles
        await MainActor.run {
            loadIdentities()
        }
        
        for group in groups {
            
            // Check if any child is already linked to this group
            let alreadyLinked = childIdentities.contains { $0.profile.mlsGroupIds.contains(group.mlsGroupId) }
            if alreadyLinked {
                continue
            }
            
            await tryLinkGroupToChildProfile(
                groupId: group.mlsGroupId,
                groupName: group.name,
                groupDescription: group.description
            )
        }
        
    }

    /// Publishes a key package to relays if we haven't already in this session.
    /// This ensures other parents can discover our key packages via Nostr.
    func publishKeyPackageIfNeeded() {
        guard !hasPublishedKeyPackage else { return }
        Task {
            await publishKeyPackageToRelays()
        }
    }

    /// Publishes a new key package to configured Nostr relays.
    /// Call this when generating a new invite to ensure key packages are available.
    func publishKeyPackageToRelays() async {
        do {
            let parentIdentity = try ensureParentIdentityLoaded()
            let relays = await environment.relayDirectory.currentRelayURLs()
            guard !relays.isEmpty else {
                logger.warning("No relays configured, cannot publish key package")
                return
            }
            let relayStrings = relays.map(\.absoluteString)
            _ = try await createParentKeyPackage(
                relays: relays,
                relayStrings: relayStrings,
                parentIdentity: parentIdentity
            )
            hasPublishedKeyPackage = true
            logger.info("✅ Key package published to relays")
        } catch {
            logger.error("Unable to publish key package: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func updateCache(with video: VideoModel) {
        if let index = videos.firstIndex(where: { $0.id == video.id }) {
            videos[index] = video
        } else {
            videos.append(video)
        }
    }

    private func totalSize(at url: URL) -> Int64 {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    func loadRelays() {
        Task {
            async let endpointsTask = environment.relayDirectory.allEndpoints()
            async let statusesTask = environment.syncCoordinator.relayStatuses()
            let endpoints = await endpointsTask
            let statuses = await statusesTask
            await MainActor.run {
                self.relayEndpoints = endpoints
                self.relayStatuses = statuses
            }
        }
    }

    func setRelay(id: String, enabled: Bool) {
        guard let endpoint = relayEndpoints.first(where: { $0.id == id }), let url = endpoint.url else { return }

        Task {
            await environment.relayDirectory.setRelay(url, enabled: enabled)
            await environment.syncCoordinator.refreshRelays()
            async let endpointsTask = environment.relayDirectory.allEndpoints()
            async let statusesTask = environment.syncCoordinator.relayStatuses()
            let endpoints = await endpointsTask
            let statuses = await statusesTask
            await MainActor.run {
                self.relayEndpoints = endpoints
                self.relayStatuses = statuses
            }
        }
    }

    func removeRelay(id: String) {
        guard let endpoint = relayEndpoints.first(where: { $0.id == id }), let url = endpoint.url else { return }

        Task {
            await environment.relayDirectory.removeRelay(url)
            await environment.syncCoordinator.refreshRelays()
            async let endpointsTask = environment.relayDirectory.allEndpoints()
            async let statusesTask = environment.syncCoordinator.relayStatuses()
            let endpoints = await endpointsTask
            let statuses = await statusesTask
            await MainActor.run {
                self.relayEndpoints = endpoints
                self.relayStatuses = statuses
            }
        }
    }

    func addRelay() {
        let trimmed = newRelayURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), ["ws", "wss"].contains(url.scheme?.lowercased() ?? "") else {
            errorMessage = "Please enter a valid wss:// relay URL."
            return
        }

        newRelayURL = ""
        Task {
            await environment.relayDirectory.addRelay(url)
            await environment.syncCoordinator.refreshRelays()
            async let endpointsTask = environment.relayDirectory.allEndpoints()
            async let statusesTask = environment.syncCoordinator.relayStatuses()
            let endpoints = await endpointsTask
            let statuses = await statusesTask
            await MainActor.run {
                self.relayEndpoints = endpoints
                self.relayStatuses = statuses
            }
        }
    }

    func loadIdentities() {
        do {
            parentIdentity = try environment.identityManager.parentIdentity()
            updateParentKeyCache(parentIdentity)
            let profiles = try environment.profileStore.fetchProfiles()
            childIdentities = profiles.map { profile in
                let identity = environment.identityManager.childIdentity(for: profile)
                let metadata: ChildProfileModel?
                if let identity {
                    do {
                        metadata = try environment.childProfileStore.profile(for: identity.publicKeyHex)
                    } catch {
                        metadata = nil
                    }
                } else {
                    metadata = nil
                }
                return ChildIdentityItem(
                    profile: profile,
                    identity: identity,
                    publishedMetadata: metadata
                )
            }
            childKeyLookup.removeAll()
            for item in childIdentities {
                if let identity = item.identity {
                    let hex = identity.publicKeyHex.lowercased()
                    childKeyLookup[hex] = item
                    if let bech32 = identity.publicKeyBech32?.lowercased() {
                        childKeyLookup[bech32] = item
                    }
                }
            }
            let existingIDs = Set(childIdentities.map { $0.id })
            childSecretVisibility = childSecretVisibility.intersection(existingIDs)
            publishingChildIDs = publishingChildIDs.intersection(existingIDs)
            // Note: refreshSubscriptions is now called explicitly by callers when needed
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadRelationships() {
        // Using MDK groups directly
    }

    func refreshConnections() {
        Task {
            await environment.syncCoordinator.refreshSubscriptions()
        }
    }


    func groupSummary(for child: ChildIdentityItem) -> GroupSummary? {
        guard let groupId = child.profile.primaryGroupId else { return nil }
        return groupSummaries[groupId]
    }
    
    func groupSummaries(for child: ChildIdentityItem) -> [GroupSummary] {
        // If there's only one child profile, show ALL groups (they all belong to this child)
        if childIdentities.count == 1 {
            return Array(groupSummaries.values).sorted { $0.name < $1.name }
        }

        // Multiple children: return groups this child is explicitly linked to
        return child.profile.mlsGroupIds.compactMap { groupSummaries[$0] }.sorted { $0.name < $1.name }
    }


    func totalAvailableRemoteShares() -> Int {
        shareStatsByChild.values.reduce(0) { $0 + $1.availableCount }
    }

    func inboundReports() -> [ReportModel] {
        reports.filter { !$0.isOutbound }
    }

    func outboundReports() -> [ReportModel] {
        reports.filter { $0.isOutbound }
    }

    func markReportReviewed(_ report: ReportModel) {
        Task {
            do {
                try await environment.reportStore.updateStatus(
                    reportId: report.id,
                    status: .acknowledged,
                    action: report.actionTaken,
                    lastActionAt: Date()
                )
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func dismissReport(_ report: ReportModel) {
        Task {
            do {
                try await environment.reportStore.updateStatus(
                    reportId: report.id,
                    status: .dismissed,
                    action: report.actionTaken,
                    lastActionAt: Date()
                )
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }


    func approvedParentKeys(forChild childId: UUID) -> [String] {
        guard let parentIdentity else { return [] }
        let localParentHex = parentIdentity.publicKeyHex.lowercased()
        let localVariants = localParentKeyVariants

        guard let childItem = childIdentities.first(where: { $0.id == childId }),
              let childIdentity = childItem.identity else {
            return []
        }

        // Approved parents tracked via MDK groups
        return []
    }


    func isApprovedParent(_ key: String, forChild childId: UUID) -> Bool {
        guard let scanned = ParentIdentityKey(string: key) else { return false }
        return approvedParentKeys(forChild: childId).contains {
            $0.caseInsensitiveCompare(scanned.hex) == .orderedSame
        }
    }


    func childDeviceInvite(for child: ChildIdentityItem) -> ChildDeviceInvite? {
        // Children no longer have separate keys - this feature is deprecated
        // Child device invites are no longer supported
        return nil
    }

    func followInvite(for child: ChildIdentityItem) -> FollowInvite? {
        guard
            let parentIdentity = parentIdentity ?? (try? ensureParentIdentityLoaded()),
            let childPublic = child.publicKey
        else {
            return nil
        }

        // Collect all children's public keys (Phase 3: children as Nostr identities)
        let allChildKeys = childIdentities.compactMap { $0.publicKey }

        // Key packages are no longer embedded - they're fetched from relays by the recipient
        return FollowInvite(
            version: 4,
            childName: child.profile.name,
            childPublicKey: childPublic,
            parentPublicKey: parentIdentity.publicKeyBech32 ?? parentIdentity.publicKeyHex,
            childPublicKeys: allChildKeys.isEmpty ? nil : allChildKeys
        )
    }

    /// Fetches key packages from Nostr relays for the given parent and their children.
    /// This is called when processing a FollowInvite to fetch the remote family's key packages.
    func fetchKeyPackagesFromRelay(for invite: FollowInvite) async {
        guard let normalizedParent = ParentIdentityKey(string: invite.parentPublicKey)?.hex.lowercased() else {
            keyPackageFetchState = .failed(parentKey: invite.parentPublicKey, error: "Invalid parent key format")
            return
        }

        // Check if we already have packages for this parent
        if let existingPackages = pendingParentKeyPackages[normalizedParent], !existingPackages.isEmpty {
            keyPackageFetchState = .fetched(parentKey: normalizedParent, count: existingPackages.count)
            return
        }

        // Skip if already fetching for this parent (prevents duplicate concurrent fetches)
        if case .fetching(let key) = keyPackageFetchState, key == normalizedParent {
            return
        }

        keyPackageFetchState = .fetching(parentKey: normalizedParent)

        do {
            // Fetch parent's key packages
            var allPackages = try await environment.keyPackageDiscovery.fetchKeyPackagesPolling(
                for: normalizedParent,
                timeout: 8
            )

            if allPackages.isEmpty {
                // Check if another concurrent fetch already succeeded
                if let existingPackages = pendingParentKeyPackages[normalizedParent], !existingPackages.isEmpty {
                    keyPackageFetchState = .fetched(parentKey: normalizedParent, count: existingPackages.count)
                    return
                }
                keyPackageFetchState = .failed(parentKey: normalizedParent, error: "No key packages found. Ask the other parent to refresh their invite.")
                return
            }

            // Phase 3: Also fetch key packages for remote children included in the invite
            for childKey in invite.allChildPublicKeys {
                guard let normalizedChild = ParentIdentityKey(string: childKey)?.hex.lowercased() else {
                    logger.warning("Invalid child key in invite: \(childKey.prefix(16), privacy: .public)")
                    continue
                }

                // Skip if this is the same as parent (shouldn't happen but be safe)
                guard normalizedChild != normalizedParent else { continue }

                do {
                    let childPackages = try await environment.keyPackageDiscovery.fetchKeyPackagesPolling(
                        for: normalizedChild,
                        timeout: 5
                    )
                    if !childPackages.isEmpty {
                        allPackages.append(contentsOf: childPackages)
                        logger.debug("Fetched \(childPackages.count) key package(s) for remote child")
                    }
                } catch {
                    // Non-fatal: continue even if we can't fetch child packages
                    logger.warning("Failed to fetch key packages for child \(childKey.prefix(16), privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }

            logger.info("✅ Fetched total of \(allPackages.count) key package(s) for remote family")

            pendingParentKeyPackages[normalizedParent] = allPackages
            parentKeyPackageStore.save(packages: allPackages, forParentKey: normalizedParent)
            keyPackageFetchState = .fetched(parentKey: normalizedParent, count: allPackages.count)
        } catch {
            keyPackageFetchState = .failed(parentKey: normalizedParent, error: error.localizedDescription)
        }
    }

    /// Legacy method for storing key packages from invite (for backwards compatibility with v2 invites).
    /// New v3 invites don't include key packages - they're fetched from relays.
    func storePendingKeyPackages(from invite: FollowInvite) {
        // For backwards compatibility, check if this is an old v2 invite with embedded packages
        // New v3 invites should use fetchKeyPackagesFromRelay instead
        guard let normalizedParent = ParentIdentityKey(string: invite.parentPublicKey)?.hex.lowercased() else {
            return
        }

        // Check if we already have packages for this parent
        if let existingPackages = pendingParentKeyPackages[normalizedParent], !existingPackages.isEmpty {
            keyPackageFetchState = .fetched(parentKey: normalizedParent, count: existingPackages.count)
            return
        }

        // No embedded packages in v3 invites - trigger async fetch
        Task {
            await fetchKeyPackagesFromRelay(for: invite)
        }
    }

    func hasPendingKeyPackages(for parentKey: String) -> Bool {
        guard let normalized = ParentIdentityKey(string: parentKey)?.hex.lowercased() else {
            return false
        }
        guard let packages = pendingParentKeyPackages[normalized] else {
            return false
        }
        return !packages.isEmpty
    }

    @discardableResult
    private func inviteParentToGroup(
        child: ChildIdentityItem,
        identity: ChildIdentity,
        keyPackages: [String],
        normalizedParentKey: String
    ) async throws -> String {

        // Note: Each parent-to-parent connection gets its own group.
        // Even if this child already has a group with another parent,
        // we create a new group for this specific connection.
        // The mlsGroupId on the Profile is just for the "primary" group (legacy field).

        // Create new group with both parents as members
        let parentIdentity = try ensureParentIdentityLoaded()
        let relays = await environment.relayDirectory.currentRelayURLs()
        guard !relays.isEmpty else {
            throw GroupMembershipWorkflowError.relaysUnavailable
        }
        let relayStrings = relays.map(\.absoluteString)

        // Build group name with both parent names
        let groupName = await buildGroupName(
            localParentKey: parentIdentity.publicKeyHex,
            remoteParentKey: normalizedParentKey,
            childName: child.displayName
        )

        // Collect all key packages: remote parent + local children
        var allKeyPackages = keyPackages  // Start with remote parent's key packages

        // Add local children's key packages (Phase 3: children as group members)
        for item in childIdentities {
            guard let childIdentity = item.identity else { continue }
            do {
                let childKeyPackage = try await createChildKeyPackageForGroup(
                    for: childIdentity,
                    relays: relays
                )
                allKeyPackages.append(childKeyPackage)
                logger.debug("Added key package for local child \(item.displayName, privacy: .public)")
            } catch {
                logger.error("Failed to create key package for child \(item.displayName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        // Create group with remote parent + local children as initial members
        // (creator/local parent is added automatically)
        // TODO: Multi-device sync - need MDK support to generate self-welcome for creator
        let request = GroupMembershipCoordinator.CreateGroupRequest(
            creatorPublicKeyHex: parentIdentity.publicKeyHex,
            memberKeyPackageEventsJson: allKeyPackages,
            name: groupName,
            description: "Secure sharing for \(child.displayName)",
            relays: relayStrings,
            adminPublicKeys: [parentIdentity.publicKeyHex],
            relayOverride: relays
        )
        let response = try await environment.groupMembershipCoordinator.createGroup(request: request)
        let groupId = response.result.group.mlsGroupId

        // Add this group to the profile's group list
        try environment.profileStore.addGroupId(groupId, forProfileId: identity.profile.id)

        // Update UI on main thread FIRST, before triggering notifications
        await MainActor.run {
            loadIdentities()
        }

        // Refresh the specific group summary
        await refreshGroupSummariesAsync(mlsGroupId: groupId)

        // Refresh subscriptions to include new group members (this triggers notifications)
        await environment.syncCoordinator.refreshSubscriptions()

        pendingParentKeyPackages.removeValue(forKey: normalizedParentKey)
        parentKeyPackageStore.removePackages(forParentKey: normalizedParentKey)
        return groupId
    }

    /// Creates a key package for a child to be used when adding to a group.
    /// Unlike `createChildKeyPackage`, this doesn't publish to relays - it just creates for local use.
    private func createChildKeyPackageForGroup(
        for identity: ChildIdentity,
        relays: [URL]
    ) async throws -> String {
        let relayStrings = relays.map(\.absoluteString)
        let result = try await environment.mdkActor.createKeyPackage(
            forPublicKey: identity.publicKeyHex,
            relays: relayStrings
        )
        return try KeyPackageEventEncoder.encode(
            result: result,
            signingKey: identity.keyPair
        )
    }


    @discardableResult
    func submitFollowRequest(
        childId: UUID,
        targetChildKey: String,
        targetParentKey: String
    ) async -> String? {
        let trimmedTargetChild = targetChildKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTargetParent = targetParentKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedTargetChild.isEmpty else {
            let message = "Enter the other child's public key."
            errorMessage = message
            return message
        }
        guard !trimmedTargetParent.isEmpty else {
            let message = "Enter the other parent's public key."
            errorMessage = message
            return message
        }
        guard let followerItem = childIdentities.first(where: { $0.id == childId }) else {
            let message = "Select a local child profile."
            errorMessage = message
            return message
        }
        guard let followerIdentity = followerItem.identity else {
            let message = "Generate a key for \(followerItem.displayName) before sending invites."
            errorMessage = message
            return message
        }
        guard isValidParentKey(trimmedTargetParent) else {
            let message = "Enter a valid parent public key (npub… or 64-char hex)."
            errorMessage = message
            return message
        }

        let localIdentity: ParentIdentity
        do {
            localIdentity = try ensureParentIdentityLoaded()
        } catch {
            let message = "Generate or import your parent key before sending follow requests."
            errorMessage = message
            return message
        }

        guard ParentIdentityKey(string: localIdentity.publicKeyBech32 ?? localIdentity.publicKeyHex) != nil else {
            let message = "Parent identity is malformed. Recreate your parent key and try again."
            errorMessage = message
            return message
        }
        guard let remoteParentKey = ParentIdentityKey(string: trimmedTargetParent) else {
            let message = "Enter a valid parent public key (npub… or 64-char hex)."
            errorMessage = message
            return message
        }

        let normalizedRemoteParent = remoteParentKey.hex.lowercased()
        guard let keyPackages = pendingParentKeyPackages[normalizedRemoteParent], !keyPackages.isEmpty else {
            let message = GroupMembershipWorkflowError.keyPackageMissing.errorDescription ?? "Scan the other parent's connection invite before sending a request."
            errorMessage = message
            return message
        }
        for (i, pkg) in keyPackages.enumerated() {
        }

        let groupId: String
        do {
            groupId = try await inviteParentToGroup(
                child: followerItem,
                identity: followerIdentity,
                keyPackages: keyPackages,
                normalizedParentKey: normalizedRemoteParent
            )
        } catch {
            errorMessage = error.displayMessage
            return error.displayMessage
        }

        do {
            errorMessage = nil
            loadIdentities()
            loadRelationships()
            Task {
                await environment.syncCoordinator.refreshSubscriptions()
            }
            return nil
        } catch {
            logger.error("Failed to record follow after MDK invite: \(error.localizedDescription, privacy: .public)")
            let message = error.localizedDescription
            errorMessage = message
            return message
        }
    }


    func addChildProfile(name: String, theme: ThemeDescriptor) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Enter a name for the child profile."
            return
        }
        do {
            let identity = try environment.identityManager.createChildIdentity(
                name: trimmed,
                theme: theme,
                avatarAsset: theme.defaultAvatarAsset
            )
            loadIdentities()
            childSecretVisibility.insert(identity.profile.id)
            lastCreatedChildID = identity.profile.id
            // Don't create group yet - MLS requires at least 2 members
            // Group will be created when first follow is established
            errorMessage = nil

            // Backup child keys, publish kind 0 metadata and key package to Nostr
            Task {
                await publishChildKeyBackup()
                await publishChildMetadata(for: identity.profile)
                await publishChildKeyPackage(for: identity.profile)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func generateChildKey(for profileId: UUID) {
        guard let item = childIdentities.first(where: { $0.id == profileId }) else { return }

        do {
            let identity = try environment.identityManager.ensureChildIdentity(for: item.profile)
            loadIdentities()
            childSecretVisibility.insert(profileId)
            errorMessage = nil
            Task {
                do {
                    try await ensureChildGroup(for: identity, preferredName: item.profile.name)
                } catch {
                    self.errorMessage = error.displayMessage
                }
                // Backup child keys, publish kind 0 metadata and key package to Nostr
                await publishChildKeyBackup()
                await publishChildMetadata(for: item.profile)
                await publishChildKeyPackage(for: item.profile)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshRelaysOnConnectivityError(_ error: Error) {
        if let transportError = error as? MarmotTransport.TransportError {
            if case .relaysUnavailable = transportError {
                Task {
                    await environment.syncCoordinator.refreshRelays()
                }
            }
        }
    }

    func importChildProfile(name: String, theme: ThemeDescriptor) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            errorMessage = "Enter a name for the child profile."
            return
        }

        do {
            let identity = try environment.identityManager.createChildIdentity(
                name: trimmedName,
                theme: theme,
                avatarAsset: theme.defaultAvatarAsset
            )
            loadIdentities()
            childSecretVisibility.insert(identity.profile.id)
            lastCreatedChildID = identity.profile.id
            errorMessage = nil
            Task {
                do {
                    try await ensureChildGroup(for: identity, preferredName: trimmedName)
                } catch {
                    self.errorMessage = error.displayMessage
                }
                // Backup child keys, publish kind 0 metadata and key package to Nostr
                await publishChildKeyBackup()
                await publishChildMetadata(for: identity.profile)
                await publishChildKeyPackage(for: identity.profile)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleParentSecretVisibility() {
        parentSecretVisible.toggle()
    }

    func isChildSecretVisible(_ id: UUID) -> Bool {
        childSecretVisibility.contains(id)
    }

    func toggleChildSecretVisibility(_ id: UUID) {
        if childSecretVisibility.contains(id) {
            childSecretVisibility.remove(id)
        } else {
            childSecretVisibility.insert(id)
        }
    }

    func isPublishingChild(_ id: UUID) -> Bool {
        publishingChildIDs.contains(id)
    }

    func createParentIdentity() {
        do {
            let identity = try environment.identityManager.generateParentIdentity(requireBiometrics: false)
            parentIdentity = identity
            updateParentKeyCache(identity)
            parentSecretVisible = false
            errorMessage = nil
            Task {
                await environment.syncCoordinator.refreshSubscriptions()
            }
            publishKeyPackageIfNeeded()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resetApp() {
        Task {
            await environment.resetApp()
            await MainActor.run {
                self.isUnlocked = false
                self.pinEntry = ""
                self.newPin = ""
                self.confirmPin = ""
                self.errorMessage = nil
                self.videos = []
                self.storageUsage = .empty
                self.relayEndpoints = []
                self.relayStatuses = []
                self.parentIdentity = nil
                self.parentSecretVisible = false
                self.childIdentities = []
                self.childSecretVisibility.removeAll()
                self.childKeyLookup.removeAll()
                self.localParentKeyVariants.removeAll()
                self.pendingWelcomes = []
                self.isRefreshingPendingWelcomes = false
                self.welcomeActionsInFlight.removeAll()
            }
        }
    }

    func refreshRelays() {
        Task {
            await environment.syncCoordinator.refreshRelays()
            async let endpointsTask = environment.relayDirectory.allEndpoints()
            async let statusesTask = environment.syncCoordinator.relayStatuses()
            let endpoints = await endpointsTask
            let statuses = await statusesTask
            await MainActor.run {
                self.relayEndpoints = endpoints
                self.relayStatuses = statuses
            }
        }
    }

    func refreshMarmotDiagnostics() {
        Task { @MainActor in
            guard !isRefreshingMarmotDiagnostics else { return }
            isRefreshingMarmotDiagnostics = true
            defer { isRefreshingMarmotDiagnostics = false }
            let stats = await environment.mdkActor.stats()
            marmotDiagnostics = MarmotDiagnostics(
                groupCount: stats.groupCount,
                pendingWelcomes: stats.pendingWelcomeCount
            )
        }
    }

    func refreshPendingWelcomes() async {
        guard !isRefreshingPendingWelcomes else { return }
        isRefreshingPendingWelcomes = true
        defer { isRefreshingPendingWelcomes = false }
        do {
            let welcomes = try await welcomeClient.getPendingWelcomes()

            // Get all groups from MDK and check which ones are functional (can query members)
            let allGroups = try await environment.mdkActor.getGroups()
            var functionalGroupIds: Set<String> = []
            for group in allGroups {
                do {
                    let members = try await environment.mdkActor.getMembers(inGroup: group.mlsGroupId)
                    if !members.isEmpty {
                        functionalGroupIds.insert(group.mlsGroupId)
                    }
                } catch {
                    // Group is not functional (can't query members) - don't filter its welcome
                }
            }

            logger.debug("refreshPendingWelcomes: \(welcomes.count) welcome(s), \(allGroups.count) group(s), \(functionalGroupIds.count) functional")
            for welcome in welcomes {
                let isFunctional = functionalGroupIds.contains(welcome.mlsGroupId)
                logger.debug("  Welcome mlsGroupId=\(welcome.mlsGroupId.prefix(16))... isFunctional=\(isFunctional)")
            }

            // Only filter out welcomes for groups that are functional (can query members)
            let filteredWelcomes = welcomes.filter { !functionalGroupIds.contains($0.mlsGroupId) }

            if filteredWelcomes.count != welcomes.count {
                logger.debug("Filtered out \(welcomes.count - filteredWelcomes.count) welcome(s) for functional groups")
            }

            pendingWelcomes = filteredWelcomes.map(PendingWelcomeItem.init)
        } catch {
            logger.error("Failed to load pending welcomes: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    func acceptWelcome(_ welcome: PendingWelcomeItem, linkToChildId: UUID?) async {
        guard !welcomeActionsInFlight.contains(welcome.id) else { return }
        welcomeActionsInFlight.insert(welcome.id)
        defer { welcomeActionsInFlight.remove(welcome.id) }
        do {
            try await welcomeClient.acceptWelcome(welcome: welcome.welcome)
            pendingWelcomes.removeAll { $0.id == welcome.id }
            refreshMarmotDiagnostics()
            notifyPendingWelcomeChange()
            notifyMarmotStateChange()
            await handleAcceptedWelcome(welcome.welcome, linkToChildId: linkToChildId)
        } catch {
            logger.error("Failed to accept welcome: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    func declineWelcome(_ welcome: PendingWelcomeItem) async {
        guard !welcomeActionsInFlight.contains(welcome.id) else { return }
        welcomeActionsInFlight.insert(welcome.id)
        defer { welcomeActionsInFlight.remove(welcome.id) }
        do {
            try await welcomeClient.declineWelcome(welcome: welcome.welcome)
            pendingWelcomes.removeAll { $0.id == welcome.id }
            refreshMarmotDiagnostics()
            notifyPendingWelcomeChange()
            notifyMarmotStateChange()
        } catch {
            logger.error("Failed to decline welcome: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    func isProcessingWelcome(_ welcome: PendingWelcomeItem) -> Bool {
        welcomeActionsInFlight.contains(welcome.id)
    }

    private func handleAcceptedWelcome(_ welcome: Welcome, linkToChildId: UUID?) async {
        
        approvePendingFollows(for: welcome)
        
        // Link to specified child, or try auto-matching by name
        if let childId = linkToChildId {
            do {
                try environment.profileStore.addGroupId(welcome.mlsGroupId, forProfileId: childId)
            } catch {
            }
        } else {
            await tryLinkGroupToChildProfile(
                groupId: welcome.mlsGroupId,
                groupName: welcome.groupName,
                groupDescription: welcome.groupDescription
            )
        }
        
        // Refresh subscriptions to include new group members
        await environment.syncCoordinator.refreshSubscriptions()
        
        // Reload identities to update profile associations
        await MainActor.run {
            loadIdentities()
        }
        
        // Explicitly refresh group summaries for the new group
        refreshGroupSummaries(mlsGroupId: welcome.mlsGroupId)
    }
    
    private func buildGroupName(
        localParentKey: String,
        remoteParentKey: String?,
        childName: String
    ) async -> String {
        GroupNameFormatter.friendlyGroupName(
            localParentKey: localParentKey,
            remoteParentKey: remoteParentKey,
            childName: childName,
            parentProfileStore: environment.parentProfileStore
        )
    }

    private func parentDisplayName(for key: String) -> String? {
        GroupNameFormatter.parentDisplayName(for: key, store: environment.parentProfileStore)
    }
    
    /// Links a group to a child profile.
    /// Since videos carry their own attribution (child npub), groups are just delivery containers.
    /// For single-child families, all groups automatically belong to that child.
    private func tryLinkGroupToChildProfile(
        groupId: String,
        groupName: String,
        groupDescription: String? = nil
    ) async {
        // If there's only one child profile, all groups belong to that child
        guard let onlyChild = childIdentities.first else { return }

        // Skip if already linked
        if onlyChild.profile.mlsGroupIds.contains(groupId) { return }

        do {
            try environment.profileStore.addGroupId(groupId, forProfileId: onlyChild.id)
            await MainActor.run {
                loadIdentities()
            }
        } catch {
            // Group linking failed, video attribution still works via npub in messages
        }
    }

    private func observeMarmotNotifications() {
        let center = NotificationCenter.default
        let pendingObserver = center.addObserver(
            forName: .marmotPendingWelcomesDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handlePendingWelcomeNotification()
            }
        }
        let stateObserver = center.addObserver(
            forName: .marmotStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleMarmotStateNotification()
            }
        }
        let messageObserver = center.addObserver(
            forName: .marmotMessagesDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleMarmotMessagesNotification(notification)
            }
        }
        marmotObservers.append(contentsOf: [pendingObserver, stateObserver, messageObserver])
    }

    private func observeParentProfileChanges() {
        let observer = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let inserted = notification.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject>,
                  let updated = notification.userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject> else {
                return
            }
            let changedProfiles = inserted.union(updated).contains { object in
                object.entity.name == "ParentProfileEntity"
            }
            if changedProfiles {
                Task { await self.refreshGroupSummariesAsync() }
            }
        }
        marmotObservers.append(observer)
    }

    private func handlePendingWelcomeNotification() {
        // Always refresh - don't wait for user to unlock or visit the tab
        Task { [weak self] in
            await self?.refreshPendingWelcomes()
        }
        refreshMarmotDiagnostics()
    }

    private func handleMarmotStateNotification() {
        // Always refresh state, even if not unlocked - keeps internal state current
        refreshMarmotDiagnostics()
        Task { [weak self] in
            await self?.refreshMembershipSurfaces()
            // Also refresh pending welcomes since state change might mean new welcomes
            await self?.refreshPendingWelcomes()
        }
        refreshGroupSummaries()
        refreshRemoteShareStats()
    }

    private func handleMarmotMessagesNotification(_ notification: Notification) {
        refreshRemoteShareStats()
        if let groupId = notification.userInfo?["mlsGroupId"] as? String {
            refreshGroupSummaries(mlsGroupId: groupId)
        } else {
            refreshGroupSummaries()
        }
    }

    @MainActor
    private func refreshMembershipSurfaces() {
        loadIdentities()
        loadRelationships()
    }

    private func refreshGroupSummaries(mlsGroupId: String? = nil) {
        Task { [weak self] in
            await self?.refreshGroupSummariesAsync(mlsGroupId: mlsGroupId)
        }
    }
    
    private func refreshGroupSummariesAsync(mlsGroupId: String? = nil) async {
        do {
            if let groupId = mlsGroupId {
                guard let group = try await self.environment.mdkActor.getGroup(mlsGroupId: groupId) else {
                    logger.debug("refreshGroupSummaries: getGroup returned nil for \(groupId.prefix(16))...")
                    await MainActor.run {
                        self.groupSummaries.removeValue(forKey: groupId)
                    }
                    return
                }
                if let summary = await self.buildGroupSummary(group) {
                    await MainActor.run {
                        self.groupSummaries[groupId] = summary
                    }
                }
            } else {
                let groups = try await self.environment.mdkActor.getGroups()
                logger.debug("refreshGroupSummaries: getGroups returned \(groups.count) group(s)")
                var summaries: [String: GroupSummary] = [:]
                for group in groups {
                    logger.debug("  Group: \(group.mlsGroupId.prefix(16))... state=\(group.state)")
                    if let summary = await self.buildGroupSummary(group) {
                        summaries[group.mlsGroupId] = summary
                        logger.debug("    -> Built summary OK")
                    } else {
                        logger.debug("    -> buildGroupSummary returned nil")
                    }
                }
                await MainActor.run {
                    self.groupSummaries = summaries
                    self.logger.debug("refreshGroupSummaries: set \(summaries.count) summaries")
                }
            }
        } catch {
            self.logger.error("Failed to refresh Marmot groups: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func makeFriendlyGroupName(group: Group, members: [String]) -> String {
        let localKeyHex = try? environment.identityManager.parentIdentity()?.publicKeyHex
        let localKey = GroupNameFormatter.canonicalParentKey(localKeyHex)

        return GroupNameFormatter.friendlyGroupName(
            group: group,
            members: members,
            localParentKey: localKey,
            parentProfileStore: environment.parentProfileStore
        )
    }

    private func buildGroupSummary(_ group: Group) async -> GroupSummary? {
        do {
            logger.debug("buildGroupSummary: building for \(group.mlsGroupId.prefix(16))...")
            async let relaysTask = environment.mdkActor.getRelays(inGroup: group.mlsGroupId)
            async let membersTask = environment.mdkActor.getMembers(inGroup: group.mlsGroupId)
            let relays = try await relaysTask
            let members = try await membersTask
            logger.debug("  relays=\(relays.count), members=\(members.count)")
            let lastMessage: Date?
            if let timestamp = group.lastMessageAt {
                lastMessage = Date(timeIntervalSince1970: TimeInterval(timestamp))
            } else {
                lastMessage = nil
            }
            let friendlyName = makeFriendlyGroupName(group: group, members: members)
            // If we can query members, the group is functional - treat as "active"
            // regardless of MDK's reported state (works around MDK state bug)
            let effectiveState = members.isEmpty ? group.state : "active"
            return GroupSummary(
                id: group.mlsGroupId,
                name: group.name,
                displayName: friendlyName,
                description: group.description,
                state: effectiveState,
                memberCount: members.count,
                adminCount: group.adminPubkeys.count,
                relayCount: relays.count,
                lastMessageAt: lastMessage
            )
        } catch {
            logger.error("Failed to build Marmot group summary: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func refreshRemoteShareStats() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let summaries = try self.environment.remoteVideoStore.shareSummaries()
                var mapping: [String: RemoteShareStats] = [:]
                for summary in summaries {
                    let canonical = ParentIdentityKey.normalizedHex(from: summary.ownerChild) ?? summary.ownerChild.lowercased()
                    mapping[canonical] = RemoteShareStats(
                        availableCount: summary.availableCount,
                        revokedCount: summary.revokedCount,
                        deletedCount: summary.deletedCount,
                        blockedCount: summary.blockedCount,
                        lastSharedAt: summary.lastSharedAt
                    )
                }
                await MainActor.run {
                    self.shareStatsByChild = mapping
                }
            } catch {
                self.logger.error("Failed to refresh remote share stats: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func approvePendingFollows(for welcome: Welcome) {
        // When a welcome is accepted, the user is automatically added to the group
        logger.info("Accepted welcome for group \(welcome.mlsGroupId, privacy: .public)")
    }

    private func notifyPendingWelcomeChange() {
        NotificationCenter.default.post(name: .marmotPendingWelcomesDidChange, object: nil)
    }

    private func notifyMarmotStateChange() {
        NotificationCenter.default.post(name: .marmotStateDidChange, object: nil)
    }

    func status(for endpoint: RelayDirectory.Endpoint) -> RelayHealth? {
        relayStatuses.first {
            $0.url.absoluteString.caseInsensitiveCompare(endpoint.urlString) == .orderedSame
        }
    }

    private func updateParentKeyCache(_ identity: ParentIdentity?) {
        guard let identity else {
            localParentKeyVariants.removeAll()
            parentProfile = nil
            return
        }

        var variants: Set<String> = []
        variants.insert(identity.publicKeyHex.lowercased())
        if let bech32 = identity.publicKeyBech32?.lowercased() {
            variants.insert(bech32)
        }
        for variant in normalizedKeyVariants(identity.publicKeyHex) {
            variants.insert(variant.lowercased())
        }
        localParentKeyVariants = variants

        parentProfile = try? environment.parentProfileStore.profile(for: identity.publicKeyHex.lowercased())
    }

    private func childItem(forKey key: String) -> ChildIdentityItem? {
        for variant in normalizedKeyVariants(key) {
            if let item = childKeyLookup[variant] {
                return item
            }
        }
        return nil
    }


    func isValidParentKey(_ key: String) -> Bool {
        ParentIdentityKey(string: key) != nil
    }

    private func ensureChildGroup(for identity: ChildIdentity, preferredName: String) async throws {
        guard identity.profile.mlsGroupIds.isEmpty else { return }

        let parentIdentity = try ensureParentIdentityLoaded()
        let relays = await environment.relayDirectory.currentRelayURLs()
        guard !relays.isEmpty else {
            throw GroupMembershipWorkflowError.relaysUnavailable
        }
        let relayStrings = relays.map(\.absoluteString)

        // Publish our key package to relays so other parents can discover it
        _ = try await createParentKeyPackage(
            relays: relays,
            relayStrings: relayStrings,
            parentIdentity: parentIdentity
        )
        hasPublishedKeyPackage = true

        // Creator is automatically added to the group, don't include in member list
        // Build simple group name for solo groups (no remote parent yet)
        let groupName = await buildGroupName(
            localParentKey: parentIdentity.publicKeyHex,
            remoteParentKey: nil,
            childName: preferredName
        )
        
        let request = GroupMembershipCoordinator.CreateGroupRequest(
            creatorPublicKeyHex: parentIdentity.publicKeyHex,
            memberKeyPackageEventsJson: [],  // Empty - creator joins automatically
            name: groupName,
            description: "Secure sharing for \(preferredName)",
            relays: relayStrings,
            adminPublicKeys: [parentIdentity.publicKeyHex],
            relayOverride: relays
        )
        let response = try await environment.groupMembershipCoordinator.createGroup(request: request)
        let groupId = response.result.group.mlsGroupId
        try environment.profileStore.addGroupId(groupId, forProfileId: identity.profile.id)

        // Update UI on main thread
        await MainActor.run {
            loadIdentities()
        }

        // Refresh the specific group summary
        await refreshGroupSummariesAsync(mlsGroupId: groupId)
        
        // Refresh subscriptions to include the new group
        await environment.syncCoordinator.refreshSubscriptions()
    }

    private func createParentKeyPackage(
        relays: [URL],
        relayStrings: [String],
        parentIdentity: ParentIdentity
    ) async throws -> String {
        let result = try await environment.mdkActor.createKeyPackage(
            forPublicKey: parentIdentity.publicKeyHex,
            relays: relayStrings
        )
        let eventJson = try encodeKeyPackageEvent(
            result: result,
            parentIdentity: parentIdentity
        )
        try await environment.marmotTransport.publish(
            jsonEvent: eventJson,
            relayOverride: relays
        )
        return eventJson
    }

    @discardableResult
    private func ensureParentIdentityLoaded() throws -> ParentIdentity {
        if let identity = parentIdentity {
            return identity
        }
        guard let identity = try environment.identityManager.parentIdentity() else {
            throw ShareFlowError.parentIdentityMissing
        }
        parentIdentity = identity
        updateParentKeyCache(identity)
        return identity
    }

    private func encodeKeyPackageEvent(
        result: KeyPackageResult,
        parentIdentity: ParentIdentity
    ) throws -> String {
        let tags = try result.tags.map { raw -> Tag in
            try Tag.parse(data: raw)
        }
        let event = try eventSigner.makeEvent(
            kind: MarmotEventKind.keyPackage.nostrKind,
            tags: tags,
            content: result.keyPackage,
            keyPair: parentIdentity.keyPair
        )
        return try event.asJson()
    }

    private func publishChildKeyBackup() async {
        do {
            try await environment.childKeyBackupService.publishBackup()
            logger.info("Child key backup published successfully")
        } catch {
            logger.error("Failed to publish child key backup: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Publishes kind 0 metadata for a child to Nostr relays.
    /// This makes the child discoverable as a Nostr identity with mytube_parent reference.
    private func publishChildMetadata(for profile: ProfileModel) async {
        do {
            _ = try await environment.childProfilePublisher.publishProfile(for: profile)
            logger.info("Child metadata published for \(profile.name, privacy: .public)")
        } catch {
            logger.error("Failed to publish child metadata: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Creates and publishes a key package for a child, enabling them to be added to Marmot groups.
    /// The key package is signed with the child's own keypair.
    /// - Parameters:
    ///   - identity: The child's identity containing their keypair
    ///   - relays: URLs of relays to publish to
    /// - Returns: The key package event JSON string
    @discardableResult
    private func createChildKeyPackage(
        for identity: ChildIdentity,
        relays: [URL]
    ) async throws -> String {
        let relayStrings = relays.map(\.absoluteString)
        let result = try await environment.mdkActor.createKeyPackage(
            forPublicKey: identity.publicKeyHex,
            relays: relayStrings
        )
        let eventJson = try KeyPackageEventEncoder.encode(
            result: result,
            signingKey: identity.keyPair
        )
        try await environment.marmotTransport.publish(
            jsonEvent: eventJson,
            relayOverride: relays
        )
        logger.info("📦 Published key package for child \(identity.profile.name, privacy: .public)")
        return eventJson
    }

    /// Publishes key packages for all local children to Nostr relays.
    /// This enables other parents to add our children to groups.
    private func publishAllChildKeyPackages() async {
        let relays = await environment.relayDirectory.currentRelayURLs()
        guard !relays.isEmpty else {
            logger.warning("No relays configured, cannot publish child key packages")
            return
        }

        for item in childIdentities {
            guard let identity = item.identity else { continue }
            do {
                try await createChildKeyPackage(for: identity, relays: relays)
            } catch {
                logger.error("Failed to publish key package for \(item.displayName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Publishes a key package for a single child to Nostr relays.
    private func publishChildKeyPackage(for profile: ProfileModel) async {
        guard let identity = environment.identityManager.childIdentity(for: profile) else {
            logger.warning("No identity found for child \(profile.name, privacy: .public), skipping key package publish")
            return
        }

        let relays = await environment.relayDirectory.currentRelayURLs()
        guard !relays.isEmpty else {
            logger.warning("No relays configured, cannot publish child key package")
            return
        }

        do {
            try await createChildKeyPackage(for: identity, relays: relays)
        } catch {
            logger.error("Failed to publish key package for \(profile.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func normalizedKeyVariants(_ key: String) -> [String] {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var variants: Set<String> = [trimmed.lowercased()]
        if let data = Data(hexString: trimmed) {
            variants.insert(data.hexEncodedString().lowercased())
            if let bech = try? NIP19.encodePublicKey(data) {
                variants.insert(bech.lowercased())
            }
        } else if trimmed.lowercased().hasPrefix(NIP19Kind.npub.rawValue),
                  let decoded = try? NIP19.decode(trimmed.lowercased()),
                  decoded.kind == .npub {
            let hex = decoded.data.hexEncodedString().lowercased()
            variants.insert(hex)
            if let bech = try? NIP19.encodePublicKey(decoded.data) {
                variants.insert(bech.lowercased())
            }
        }
        return Array(variants)
    }

    struct ChildIdentityItem: Identifiable {
        let profile: ProfileModel
        let identity: ChildIdentity?
        let publishedMetadata: ChildProfileModel?

        var id: UUID { profile.id }
        var displayName: String { profile.name }
        var publicKey: String? {
            identity?.publicKeyBech32 ?? identity?.publicKeyHex
        }
        var secretKey: String? {
            // Children no longer have secret keys - they are profiles owned by parents
            identity?.secretKeyBech32
        }

        var publishedName: String? {
            publishedMetadata?.bestName
        }

        var metadataUpdatedAt: Date? {
            publishedMetadata?.updatedAt
        }

        func updating(metadata: ChildProfileModel?) -> ChildIdentityItem {
            ChildIdentityItem(
                profile: profile,
                identity: identity,
                publishedMetadata: metadata
            )
        }
    }

    struct ChildDeviceInvite: Codable, Sendable, Equatable {
        struct DelegationPayload: Codable, Sendable, Equatable {
            let delegator: String
            let delegatee: String
            let conditions: String
            let signature: String
        }

        let version: Int
        let childName: String
        let childPublicKey: String
        let childSecretKey: String
        let parentPublicKey: String
        let delegation: DelegationPayload?

        var encodedURL: String? {
            guard let data = try? JSONEncoder().encode(self) else {
                return nil
            }
            let base = data.base64EncodedString()
            var components = URLComponents()
            components.scheme = "tubestr"
            components.host = "child-invite"
            components.queryItems = [
                URLQueryItem(name: "v", value: "\(version)"),
                URLQueryItem(name: "data", value: base)
            ]
            return components.url?.absoluteString
        }

        var shareText: String {
            """
            Tubestr Child Device Invite: \(childName)
            Parent: \(parentPublicKey)
            Child: \(childPublicKey)

            Open the link below on the destination device.
            """
        }

        var shareItems: [Any] {
            var items: [Any] = []
            items.append(shareText)
            if let urlString = encodedURL, let url = URL(string: urlString) {
                items.append(url)
            } else if let urlString = encodedURL {
                items.append(urlString)
            }
            return items
        }

        static func decode(from string: String) -> ChildDeviceInvite? {
            if let invite = decodeURLString(string) {
                return invite
            }
            let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;|<>\"'()[]{}"))
            let tokens = string.components(separatedBy: separators)
            for token in tokens {
                if let invite = decodeURLString(token) {
                    return invite
                }
            }
            return nil
        }

        private static func decodeURLString(_ string: String) -> ChildDeviceInvite? {
            guard let url = URL(string: string),
                  (url.scheme?.caseInsensitiveCompare("tubestr") == .orderedSame || url.scheme?.caseInsensitiveCompare("mytube") == .orderedSame),
                  url.host?.caseInsensitiveCompare("child-invite") == .orderedSame,
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let dataParam = components.queryItems?.first(where: { $0.name == "data" })?.value,
                  let decodedData = Data(base64Encoded: dataParam)
            else { return nil }
            return try? JSONDecoder().decode(ChildDeviceInvite.self, from: decodedData)
        }
    }

    struct FollowInvite: Codable, Sendable, Equatable {
        let version: Int
        let childName: String?
        let childPublicKey: String  // Primary child's public key (for v1-v3 compatibility)
        let parentPublicKey: String
        // Note: parentKeyPackages removed - now fetched from Nostr relays via KeyPackageDiscovery

        /// All children's public keys (Phase 3: children as Nostr identities)
        /// Added in v4. Recipients use these to fetch key packages for all children.
        let childPublicKeys: [String]?

        init(
            version: Int,
            childName: String?,
            childPublicKey: String,
            parentPublicKey: String,
            childPublicKeys: [String]? = nil
        ) {
            self.version = version
            self.childName = childName
            self.childPublicKey = childPublicKey
            self.parentPublicKey = parentPublicKey
            self.childPublicKeys = childPublicKeys
        }

        /// Returns all children's public keys, with fallback to single childPublicKey for older versions
        var allChildPublicKeys: [String] {
            if let keys = childPublicKeys, !keys.isEmpty {
                return keys
            }
            return [childPublicKey]
        }

        var encodedURL: String? {
            guard let data = try? JSONEncoder().encode(self) else {
                return nil
            }
            let base = data.base64EncodedString()
            var components = URLComponents()
            components.scheme = "tubestr"
            components.host = "follow-invite"
            components.queryItems = [
                URLQueryItem(name: "v", value: "\(version)"),
                URLQueryItem(name: "data", value: base)
            ]
            return components.url?.absoluteString
        }

        var shareText: String {
            let nameDescriptor = childName.map { " (\($0))" } ?? ""
            let childCount = allChildPublicKeys.count
            let childrenSuffix = childCount > 1 ? " +\(childCount - 1) more" : ""
            return """
            Tubestr Family Invite\(nameDescriptor)\(childrenSuffix)
            Parent: \(parentPublicKey)
            Profile: \(childPublicKey)

            Open the link below on the other parent's device.
            """
        }

        var shareItems: [Any] {
            var items: [Any] = [shareText]
            if let urlString = encodedURL, let url = URL(string: urlString) {
                items.append(url)
            } else if let urlString = encodedURL {
                items.append(urlString)
            }
            return items
        }

        static func decode(from string: String) -> FollowInvite? {
            if let invite = decodeURLString(string) {
                return invite
            }

            let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { return nil }

            let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;|&"))
            let tokens = normalized.components(separatedBy: separators).filter { !$0.isEmpty }
            var parentValue: String?
            var childValue: String?

            for token in tokens {
                let parts = token.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                let key = parts[0].lowercased()
                let value = parts[1]
                if key == "parent" || key == "parentnpub" {
                    parentValue = value
                } else if key == "child" || key == "childnpub" {
                    childValue = value
                }
            }

            if let parentValue, let childValue {
                return FollowInvite(
                    version: 1,
                    childName: nil,
                    childPublicKey: childValue,
                    parentPublicKey: parentValue
                )
            }

            return nil
        }

        private static func decodeURLString(_ string: String) -> FollowInvite? {
            guard let url = URL(string: string),
                  (url.scheme?.caseInsensitiveCompare("tubestr") == .orderedSame || url.scheme?.caseInsensitiveCompare("mytube") == .orderedSame),
                  url.host?.caseInsensitiveCompare("follow-invite") == .orderedSame,
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let dataParam = components.queryItems?.first(where: { $0.name == "data" })?.value,
                  let decodedData = Data(base64Encoded: dataParam)
            else { return nil }
            return try? JSONDecoder().decode(FollowInvite.self, from: decodedData)
        }
    }
}
