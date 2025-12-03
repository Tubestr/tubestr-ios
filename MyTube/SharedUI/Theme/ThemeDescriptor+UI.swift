//
//  ThemeDescriptor+UI.swift
//  MyTube
//
//  Created by Codex on 11/06/25.
//

import Foundation

extension ThemeDescriptor {
    var displayName: String {
        switch self {
        case .campfire: return "Campfire"
        case .treehouse: return "Treehouse"
        case .blanketFort: return "Blanket Fort"
        case .starlight: return "Starlight"
        }
    }

    var defaultAvatarAsset: String {
        "avatar.dolphin"
    }
}
