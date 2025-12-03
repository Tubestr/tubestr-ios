//
//  ResourceLibrary.swift
//  MyTube
//
//  Created by Codex on 10/24/25.
//

import Foundation
import UIKit

struct StickerAsset: Identifiable, Hashable {
    let id: String         // base resource name without extension or UUID for user stickers
    let filename: String   // e.g. sticker_01.png
    let fileURL: URL?      // nil for bundled stickers, URL for user-created stickers

    /// Whether this is a user-created sticker (selfie sticker)
    var isUserSticker: Bool { fileURL != nil }

    var displayName: String {
        if isUserSticker {
            return "My Sticker"
        }
        return id.components(separatedBy: CharacterSet(charactersIn: "_-"))
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .capitalized
    }

    init(id: String, filename: String, fileURL: URL? = nil) {
        self.id = id
        self.filename = filename
        self.fileURL = fileURL
    }
}

struct MusicAsset: Identifiable, Hashable {
    let id: String         // base resource name without extension
    let filename: String   // e.g. track_01.mp3

    var displayName: String {
        id.replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

struct LUTAsset: Identifiable, Hashable {
    let id: String         // base resource name without extension
    let filename: String   // e.g. dusty_light.cube

    var displayName: String {
        id.replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

enum ResourceLibrary {
    static func stickers(in bundle: Bundle = .main) -> [StickerAsset] {
        resourceFiles(extension: "png", bundle: bundle)
            .filter { $0.filename.hasPrefix("sticker_") }
            .map { StickerAsset(id: $0.nameWithoutExtension, filename: $0.filename) }
    }

    /// Load user-created stickers from the UserStickers directory
    static func userStickers(from storagePaths: StoragePaths, profileId: UUID) -> [StickerAsset] {
        let userStickersDir = storagePaths.url(for: .userStickers, profileId: profileId)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: userStickersDir,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents
            .filter { $0.pathExtension.lowercased() == "png" }
            .sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return date1 > date2  // Most recent first
            }
            .map { url in
                StickerAsset(
                    id: url.deletingPathExtension().lastPathComponent,
                    filename: url.lastPathComponent,
                    fileURL: url
                )
            }
    }

    /// Save a user sticker image and return the created asset
    static func saveUserSticker(
        image: UIImage,
        storagePaths: StoragePaths,
        profileId: UUID
    ) throws -> StickerAsset {
        let userStickersDir = storagePaths.url(for: .userStickers, profileId: profileId)

        // Ensure directory exists
        try FileManager.default.createDirectory(at: userStickersDir, withIntermediateDirectories: true)

        let id = UUID().uuidString
        let filename = "\(id).png"
        let fileURL = userStickersDir.appendingPathComponent(filename)

        guard let data = image.pngData() else {
            throw NSError(domain: "ResourceLibrary", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode image"])
        }

        try data.write(to: fileURL, options: .atomic)

        #if os(iOS)
        try? FileManager.default.setAttributes(
            [FileAttributeKey.protectionKey: FileProtectionType.complete],
            ofItemAtPath: fileURL.path
        )
        #endif

        return StickerAsset(id: id, filename: filename, fileURL: fileURL)
    }

    /// Delete a user sticker
    static func deleteUserSticker(_ sticker: StickerAsset) throws {
        guard let fileURL = sticker.fileURL else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    static func musicTracks(in bundle: Bundle = .main) -> [MusicAsset] {
        resourceFiles(extension: "mp3", bundle: bundle)
            .filter { $0.filename.hasPrefix("track_") }
            .map { MusicAsset(id: $0.nameWithoutExtension, filename: $0.filename) }
    }

    static func luts(in bundle: Bundle = .main) -> [LUTAsset] {
        resourceFiles(extension: "cube", bundle: bundle)
            .map { LUTAsset(id: $0.nameWithoutExtension, filename: $0.filename) }
    }

    static func stickerImage(named resourceName: String, in bundle: Bundle = .main) -> UIImage? {
        guard let url = bundle.url(forResource: resourceName, withExtension: "png") else {
            return nil
        }
        return UIImage(contentsOfFile: url.path)
    }

    /// Load sticker image from a StickerAsset (handles both bundled and user stickers)
    static func stickerImage(for asset: StickerAsset, in bundle: Bundle = .main) -> UIImage? {
        if let fileURL = asset.fileURL {
            return UIImage(contentsOfFile: fileURL.path)
        }
        return stickerImage(named: asset.id, in: bundle)
    }

    static func musicURL(for resourceName: String, in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: resourceName, withExtension: "mp3")
    }

    static func lutURL(for resourceName: String, in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: resourceName, withExtension: "cube")
    }

    private static func resourceFiles(extension fileExtension: String, bundle: Bundle) -> [ResourceFile] {
        guard let resourcePath = bundle.resourcePath else { return [] }
        let resourceURL = URL(fileURLWithPath: resourcePath)
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: resourceURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        return contents
            .filter { $0.pathExtension.lowercased() == fileExtension.lowercased() }
            .map { ResourceFile(url: $0) }
            .sorted { $0.filename < $1.filename }
    }

    private struct ResourceFile {
        let url: URL

        var filename: String {
            url.lastPathComponent
        }

        var nameWithoutExtension: String {
            url.deletingPathExtension().lastPathComponent
        }
    }
}
