//
//  LicenseStateStore.swift
//  aizen
//
//  Client-side license state and actions for paid plan management.
//

import Foundation
import AppKit
import os.log
import Combine

@MainActor
final class LicenseStateStore: ObservableObject {
    static let shared = LicenseStateStore()

    enum Status: Equatable {
        case unlicensed
        case checking
        case active
        case expired
        case offlineGrace(daysLeft: Int)
        case invalid(reason: String)
        case error(message: String)
    }

    @Published var status: Status = .unlicensed
    @Published var licenseType: String?
    @Published var licenseStatus: String?
    @Published var expiresAt: Date?
    @Published var lastValidatedAt: Date?
    @Published var lastMessage: String?

    @Published var licenseToken: String = ""

    var hasDeviceCredentials: Bool {
        currentDeviceAuth != nil
    }

    var hasActivePlan: Bool {
        switch status {
        case .active, .offlineGrace:
            return true
        case .checking, .unlicensed, .expired, .invalid, .error:
            return false
        }
    }

    struct PendingDeepLink {
        let token: String?
        let autoActivate: Bool
    }

    private var pendingDeepLink: PendingDeepLink?

    var hasPendingDeepLink: Bool {
        pendingDeepLink != nil
    }

    let store = LicenseStore()

    let client = LicenseClient()
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "win.aizen.app", category: "License")

    var validationTask: Task<Void, Never>?
    let validationInterval: TimeInterval = 24 * 60 * 60
    let offlineGraceDays = 7

    private init() {
        loadFromStore()
    }

    func setPendingDeepLink(token: String?, autoActivate: Bool) {
        pendingDeepLink = PendingDeepLink(token: token, autoActivate: autoActivate)
    }

    func consumePendingDeepLink() -> PendingDeepLink? {
        let value = pendingDeepLink
        pendingDeepLink = nil
        return value
    }

    // MARK: - Helpers

    var currentToken: String? {
        let trimmed = licenseToken.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var currentDeviceAuth: LicenseClient.DeviceAuth? {
        guard let deviceId = store.loadDeviceId(),
              let deviceSecret = store.loadDeviceSecret() else {
            return nil
        }
        return LicenseClient.DeviceAuth(deviceId: deviceId, deviceSecret: deviceSecret)
    }

    var deviceAuthService: LicenseDeviceAuthService {
        LicenseDeviceAuthService(store: store, client: client, logger: logger)
    }

    func offlineGraceDaysLeft(from date: Date) -> Int? {
        let elapsed = Date().timeIntervalSince(date)
        let remaining = (Double(offlineGraceDays) * 86400) - elapsed
        guard remaining > 0 else { return nil }
        return Int(ceil(remaining / 86400))
    }
}
