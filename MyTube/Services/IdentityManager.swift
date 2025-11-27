//
//  IdentityManager.swift
//  MyTube
//
//  Created by Codex on 11/06/25.
//

import Foundation
import NostrSDK

enum IdentityManagerError: Error {
    case parentIdentityAlreadyExists
    case parentIdentityMissing
    case invalidPrivateKey
    case invalidPublicKey
    case profileNotFound
    case invalidProfileName
}

struct ParentIdentity {
    let keyPair: NostrKeyPair
    let wrapKeyPair: ParentWrapKeyPair?

    var publicKeyHex: String { keyPair.publicKeyHex }
    var publicKeyBech32: String? { keyPair.publicKeyBech32 }
    var secretKeyBech32: String? { keyPair.secretKeyBech32 }

    var wrapPublicKeyBase64: String? {
        guard let wrapKeyPair else { return nil }
        return try? wrapKeyPair.publicKeyBase64()
    }
}

struct ChildIdentity {
    let profile: ProfileModel
    let keyPair: NostrKeyPair

    var publicKeyHex: String { keyPair.publicKeyHex }
    var publicKeyBech32: String? { keyPair.publicKeyBech32 }
    var secretKeyBech32: String? { keyPair.secretKeyBech32 }
}


/// Coordinates key generation, import, and export for parent/child identities.
final class IdentityManager {
    private let keyStore: KeychainKeyStore
    private let profileStore: ProfileStore

    init(keyStore: KeychainKeyStore, profileStore: ProfileStore) {
        self.keyStore = keyStore
        self.profileStore = profileStore
    }

    func hasParentIdentity() -> Bool {
        (try? keyStore.fetchKeyPair(role: .parent)) != nil
    }

    func parentIdentity() throws -> ParentIdentity? {
        guard let pair = try keyStore.fetchKeyPair(role: .parent) else {
            return nil
        }
        let wrapPair = try keyStore.fetchParentWrapKeyPair() ?? keyStore.ensureParentWrapKeyPair(requireBiometrics: false)
        return ParentIdentity(keyPair: pair, wrapKeyPair: wrapPair)
    }

    @discardableResult
    func generateParentIdentity(requireBiometrics: Bool) throws -> ParentIdentity {
        guard try keyStore.fetchKeyPair(role: .parent) == nil else {
            throw IdentityManagerError.parentIdentityAlreadyExists
        }
        let secret = NostrSDK.SecretKey.generate()
        let pair = try NostrKeyPair(secretKey: secret)
        try keyStore.storeKeyPair(pair, role: .parent, requireBiometrics: requireBiometrics)
        let wrapPair = try keyStore.ensureParentWrapKeyPair(requireBiometrics: requireBiometrics)
        return ParentIdentity(keyPair: pair, wrapKeyPair: wrapPair)
    }

    @discardableResult
    func importParentIdentity(_ input: String, requireBiometrics: Bool) throws -> ParentIdentity {
        guard try keyStore.fetchKeyPair(role: .parent) == nil else {
            throw IdentityManagerError.parentIdentityAlreadyExists
        }
        let data = try decodePrivateKey(input)
        let pair = try NostrKeyPair(privateKeyData: data)
        try keyStore.storeKeyPair(pair, role: .parent, requireBiometrics: requireBiometrics)
        let wrapPair = try keyStore.ensureParentWrapKeyPair(requireBiometrics: requireBiometrics)
        return ParentIdentity(keyPair: pair, wrapKeyPair: wrapPair)
    }

    func parentWrapKeyPair(requireBiometrics: Bool = false) throws -> ParentWrapKeyPair {
        if let existing = try keyStore.fetchParentWrapKeyPair() {
            return existing
        }
        return try keyStore.ensureParentWrapKeyPair(requireBiometrics: requireBiometrics)
    }

    func createChildIdentity(
        name: String,
        theme: ThemeDescriptor,
        avatarAsset: String
    ) throws -> ChildIdentity {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw IdentityManagerError.invalidProfileName
        }

        guard try keyStore.fetchKeyPair(role: .parent) != nil else {
            throw IdentityManagerError.parentIdentityMissing
        }

        let profile = try profileStore.createProfile(
            name: trimmed,
            theme: theme,
            avatarAsset: avatarAsset
        )

        // Generate random Nostr keypair for child
        let secretKey = NostrSDK.SecretKey.generate()
        let keyPair = try NostrKeyPair(secretKey: secretKey)
        try keyStore.storeKeyPair(keyPair, role: .child(id: profile.id), requireBiometrics: false)

        return ChildIdentity(profile: profile, keyPair: keyPair)
    }

    func childIdentity(for profile: ProfileModel) -> ChildIdentity? {
        guard let keyPair = try? keyStore.fetchKeyPair(role: .child(id: profile.id)) else {
            return nil
        }
        return ChildIdentity(profile: profile, keyPair: keyPair)
    }

    func allChildIdentities() throws -> [ChildIdentity] {
        let profiles = try profileStore.fetchProfiles()
        return profiles.compactMap { childIdentity(for: $0) }
    }

    func ensureChildIdentity(for profile: ProfileModel) throws -> ChildIdentity {
        // Return existing identity if keypair already exists
        if let existing = childIdentity(for: profile) {
            return existing
        }

        // Generate new keypair for this profile
        let secretKey = NostrSDK.SecretKey.generate()
        let keyPair = try NostrKeyPair(secretKey: secretKey)
        try keyStore.storeKeyPair(keyPair, role: .child(id: profile.id), requireBiometrics: false)

        return ChildIdentity(profile: profile, keyPair: keyPair)
    }

    private func decodePrivateKey(_ string: String) throws -> Data {
        let cleaned = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw IdentityManagerError.invalidPrivateKey }

        let lower = cleaned.lowercased()
        if let data = Data(hexString: lower), data.count == 32 {
            return data
        }
        if lower.hasPrefix(NIP19Kind.nsec.rawValue) {
            let decoded = try NIP19.decode(lower)
            guard decoded.kind == .nsec else {
                throw IdentityManagerError.invalidPrivateKey
            }
            return decoded.data
        }
        throw IdentityManagerError.invalidPrivateKey
    }
}
