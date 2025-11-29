//
//  ProfileStore.swift
//  MyTube
//
//  Created by Codex on 10/24/25.
//

import CoreData
import Foundation

enum ProfileStoreError: Error {
    case entityMissing
}

final class ProfileStore: ObservableObject {
    private let persistence: PersistenceController

    init(persistence: PersistenceController) {
        self.persistence = persistence
    }

    func fetchProfiles() throws -> [ProfileModel] {
        let request = ProfileEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ProfileEntity.name, ascending: true)]
        let entities = try persistence.viewContext.fetch(request)
        return entities.compactMap(ProfileModel.init(entity:))
    }

    func createProfile(name: String, theme: ThemeDescriptor, avatarAsset: String) throws -> ProfileModel {
        try createProfileWithId(id: UUID(), name: name, theme: theme, avatarAsset: avatarAsset)
    }

    func createProfileWithId(id: UUID, name: String, theme: ThemeDescriptor, avatarAsset: String) throws -> ProfileModel {
        let entity = ProfileEntity(context: persistence.viewContext)
        entity.id = id
        entity.name = name
        entity.theme = theme.rawValue
        entity.avatarAsset = avatarAsset
        entity.mlsGroupId = nil
        entity.mlsGroupIdsJSON = "[]"
        try persistence.viewContext.save()
        guard let model = ProfileModel(entity: entity) else {
            throw ProfileStoreError.entityMissing
        }
        return model
    }

    func updateProfile(_ model: ProfileModel) throws {
        let request = ProfileEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", model.id as CVarArg)
        request.fetchLimit = 1
        guard let entity = try persistence.viewContext.fetch(request).first else {
            throw ProfileStoreError.entityMissing
        }
        entity.name = model.name
        entity.theme = model.theme.rawValue
        entity.avatarAsset = model.avatarAsset
        entity.mlsGroupIds = model.mlsGroupIds
        try persistence.viewContext.save()
    }

    /// Adds a group ID to the profile if not already present.
    func addGroupId(_ groupId: String, forProfileId profileId: UUID) throws {
        let request = ProfileEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", profileId as CVarArg)
        request.fetchLimit = 1
        guard let entity = try persistence.viewContext.fetch(request).first else {
            throw ProfileStoreError.entityMissing
        }
        entity.addGroupId(groupId)
        try persistence.viewContext.save()
    }

    /// Removes a group ID from the profile if present.
    func removeGroupId(_ groupId: String, forProfileId profileId: UUID) throws {
        let request = ProfileEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", profileId as CVarArg)
        request.fetchLimit = 1
        guard let entity = try persistence.viewContext.fetch(request).first else {
            throw ProfileStoreError.entityMissing
        }
        entity.removeGroupId(groupId)
        try persistence.viewContext.save()
    }
}
