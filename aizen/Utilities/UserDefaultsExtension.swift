//
//  UserDefaultsExtension.swift
//  aizen
//

import Foundation

extension UserDefaults {
    /// Shared UserDefaults instance that uses the appropriate suite based on bundle ID.
    /// Nightly builds use a separate suite to isolate settings from release builds.
    static var app: UserDefaults {
        guard let bundleID = Bundle.main.bundleIdentifier else {
            return .standard
        }
        let suiteName = bundleID.contains(".nightly") ? "win.aizen.app.nightly" : "win.aizen.app"
        return UserDefaults(suiteName: suiteName) ?? .standard
    }

    /// Whether the current app is a nightly/development build
    static var isNightlyBuild: Bool {
        Bundle.main.bundleIdentifier?.contains(".nightly") ?? false
    }
}
