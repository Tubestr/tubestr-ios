//
//  ProfileEntity+GroupIds.swift
//  MyTube
//

import CoreData
import Foundation

extension ProfileEntity {
    /// Parsed array of MLS group IDs from the JSON storage.
    var mlsGroupIds: [String] {
        get {
            guard let json = mlsGroupIdsJSON, !json.isEmpty else { return [] }
            guard let data = json.data(using: .utf8),
                  let ids = try? JSONDecoder().decode([String].self, from: data)
            else { return [] }
            return ids
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let json = String(data: data, encoding: .utf8)
            else {
                mlsGroupIdsJSON = "[]"
                return
            }
            mlsGroupIdsJSON = json
        }
    }

    /// Adds a group ID if not already present.
    func addGroupId(_ groupId: String) {
        var ids = mlsGroupIds
        guard !ids.contains(groupId) else { return }
        ids.append(groupId)
        mlsGroupIds = ids
    }

    /// Removes a group ID if present.
    func removeGroupId(_ groupId: String) {
        var ids = mlsGroupIds
        ids.removeAll { $0 == groupId }
        mlsGroupIds = ids
    }

    /// Returns true if the profile is associated with the given group.
    func hasGroupId(_ groupId: String) -> Bool {
        mlsGroupIds.contains(groupId)
    }
}
