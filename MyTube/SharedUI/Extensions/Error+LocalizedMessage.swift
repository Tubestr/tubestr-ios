//
//  Error+LocalizedMessage.swift
//  MyTube
//
//  Provides a consistent way to extract user-facing error messages.
//

import Foundation

extension Error {
    /// Returns the localized error description if available, otherwise falls back to localizedDescription.
    var displayMessage: String {
        (self as? LocalizedError)?.errorDescription ?? localizedDescription
    }
}
