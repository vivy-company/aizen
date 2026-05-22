//
//  AnalyticsContextSnapshot.swift
//  aizen
//
//  Main-actor snapshot of app-level analytics context passed into the network actor.
//

import Foundation

nonisolated struct AnalyticsContextSnapshot: Sendable {
    let isEnabled: Bool
    let baseURLString: String
    let websiteId: String
    let hostname: String
    let title: String
    let language: String?
    let userAgent: String
    let installId: String
    let osName: String
    let device: String
    let channel: AnalyticsChannel
    let buildNumber: String
    let appVersion: String
    let globalProperties: [String: AnalyticsPropertyValue]

    var isConfigured: Bool {
        !baseURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !websiteId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && websiteId != "AIZEN_APP_UMAMI_WEBSITE_ID"
    }

    @MainActor
    static func current(defaults: UserDefaults = .standard, bundle: Bundle = .main) -> AnalyticsContextSnapshot {
        let appVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let buildNumber = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let channel = resolvedChannel(bundle: bundle)
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let arch = resolvedArchitecture()
        let language = Locale.current.language.languageCode?.identifier
        let licenseTier = resolvedLicenseTier()
        let baseURLString = bundle.object(forInfoDictionaryKey: "AizenUmamiBaseURL") as? String
            ?? "https://analytics.vivy.app"
        let websiteId = bundle.object(forInfoDictionaryKey: "AizenUmamiWebsiteID") as? String ?? ""

        return AnalyticsContextSnapshot(
            isEnabled: AnalyticsSettings.isEnabled(defaults: defaults),
            baseURLString: baseURLString,
            websiteId: websiteId,
            hostname: "app.aizen.win",
            title: "Aizen App",
            language: language,
            userAgent: "Aizen/\(appVersion) (\(buildNumber)); macOS \(osVersion.majorVersion).\(osVersion.minorVersion); \(arch)",
            installId: AnalyticsSettings.anonymousInstallId(defaults: defaults),
            osName: "macOS",
            device: arch,
            channel: channel,
            buildNumber: buildNumber,
            appVersion: appVersion,
            globalProperties: [
                "app_version": .string(appVersion),
                "build_number": .string(buildNumber),
                "channel": .string(channel.rawValue),
                "macos_major": .integer(osVersion.majorVersion),
                "macos_minor": .integer(osVersion.minorVersion),
                "arch": .string(arch),
                "license_tier": .string(licenseTier.rawValue),
                "analytics_schema_version": .integer(1)
            ].merging(language.map { ["locale_language": .string($0)] } ?? [:]) { current, _ in current }
        )
    }

    @MainActor
    private static func resolvedChannel(bundle: Bundle) -> AnalyticsChannel {
        #if DEBUG
        return .debug
        #else
        let bundleIdentifier = (bundle.bundleIdentifier ?? "").lowercased()
        let displayName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "").lowercased()
        if bundleIdentifier.contains("nightly") || displayName.contains("nightly") {
            return .nightly
        }
        if bundleIdentifier.isEmpty {
            return .unknown
        }
        return .stable
        #endif
    }

    @MainActor
    private static func resolvedLicenseTier() -> AnalyticsLicenseTier {
        let store = LicenseStateStore.shared
        guard store.hasActivePlan else {
            return .free
        }

        switch store.licenseType?.lowercased() {
        case "pro":
            return .pro
        case "lifetime":
            return .lifetime
        case .some:
            return .unknown
        case .none:
            return .unknown
        }
    }

    nonisolated private static func resolvedArchitecture() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}
