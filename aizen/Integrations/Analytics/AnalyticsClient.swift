//
//  AnalyticsClient.swift
//  aizen
//
//  MainActor facade for fire-and-forget product analytics.
//

import Foundation

@MainActor
final class Analytics {
    static let shared = Analytics()

    private let client: UmamiAnalyticsClient
    private let defaults: UserDefaults
    private var didRecordAppLaunch = false
    private var didRecordSettingsOpened = false

    init(
        client: UmamiAnalyticsClient = UmamiAnalyticsClient(),
        defaults: UserDefaults = .standard
    ) {
        self.client = client
        self.defaults = defaults
    }

    func track(_ event: AnalyticsEvent) {
        let context = AnalyticsContextSnapshot.current(defaults: defaults)
        guard context.isEnabled else { return }

        Task(priority: .utility) { [client] in
            await client.track(event, context: context)
        }
    }

    func recordAppLaunch() {
        guard !didRecordAppLaunch else { return }
        didRecordAppLaunch = true

        track(.appOpened)
        recordAppActiveDailyIfNeeded()
        recordUpdateInstalledIfNeeded()
    }

    func recordSettingsOpened() {
        guard !didRecordSettingsOpened else { return }
        didRecordSettingsOpened = true
        track(.settingsOpened)
    }

    private func recordAppActiveDailyIfNeeded() {
        let today = localDayKey(for: Date())
        guard defaults.string(forKey: AnalyticsSettings.lastAppActiveDailyDateKey) != today else {
            return
        }

        defaults.set(today, forKey: AnalyticsSettings.lastAppActiveDailyDateKey)
        track(.appActiveDaily)
    }

    private func recordUpdateInstalledIfNeeded() {
        let context = AnalyticsContextSnapshot.current(defaults: defaults)
        let currentBuild = context.buildNumber
        let previousBuild = defaults.string(forKey: AnalyticsSettings.lastUpdateInstalledBuildKey)
        let previousChannel = defaults.string(forKey: AnalyticsSettings.lastUpdateInstalledChannelKey)
            .flatMap(AnalyticsChannel.init(rawValue:)) ?? .unknown

        defer {
            defaults.set(currentBuild, forKey: AnalyticsSettings.lastUpdateInstalledBuildKey)
            defaults.set(context.channel.rawValue, forKey: AnalyticsSettings.lastUpdateInstalledChannelKey)
        }

        guard let previousBuild, previousBuild != currentBuild else {
            return
        }

        track(.updateInstalled(previousVersionKnown: true, previousChannel: previousChannel))
    }

    private func localDayKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return [
            components.year.map(String.init) ?? "0000",
            String(format: "%02d", components.month ?? 0),
            String(format: "%02d", components.day ?? 0)
        ].joined(separator: "-")
    }
}
