//
//  AnalyticsSettings.swift
//  aizen
//
//  Local analytics preferences and per-install anonymous identity.
//

import Foundation

enum AnalyticsSettings {
    static let isEnabledKey = "analytics.shareAnonymousUsage"
    static let anonymousInstallIdKey = "analytics.anonymousInstallId"
    static let lastAppActiveDailyDateKey = "analytics.lastAppActiveDailyDate"
    static let lastUpdateInstalledBuildKey = "analytics.lastUpdateInstalledBuild"
    static let lastUpdateInstalledChannelKey = "analytics.lastUpdateInstalledChannel"

    static let defaultIsEnabled = true

    @MainActor
    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: isEnabledKey) != nil else {
            return defaultIsEnabled
        }
        return defaults.bool(forKey: isEnabledKey)
    }

    @MainActor
    static func anonymousInstallId(defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: anonymousInstallIdKey), !existing.isEmpty {
            return existing
        }

        let created = UUID().uuidString
        defaults.set(created, forKey: anonymousInstallIdKey)
        return created
    }
}
