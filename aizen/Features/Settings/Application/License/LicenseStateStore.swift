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

    private var validationTask: Task<Void, Never>?
    let validationInterval: TimeInterval = 24 * 60 * 60
    let offlineGraceDays = 7

    private init() {
        loadFromStore()
    }

    func start() {
        scheduleValidationTimer()
        Task {
            await validateIfNeeded()
        }
    }

    func setPendingDeepLink(token: String?, autoActivate: Bool) {
        pendingDeepLink = PendingDeepLink(token: token, autoActivate: autoActivate)
    }

    func consumePendingDeepLink() -> PendingDeepLink? {
        let value = pendingDeepLink
        pendingDeepLink = nil
        return value
    }

    // MARK: - Public Actions

    @discardableResult
    func activate(token: String, deviceName: String) async -> Bool {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            status = .invalid(reason: "Enter a license key")
            return false
        }

        status = .checking
        lastMessage = nil

        let fingerprint = deviceAuthService.getOrCreateDeviceFingerprint()

        do {
            let response = try await client.activate(
                token: trimmedToken,
                deviceFingerprint: fingerprint,
                deviceName: deviceName
            )

            if response.success == true,
               let deviceId = response.deviceId,
               let deviceSecret = response.deviceSecret {
                store.saveToken(trimmedToken)
                store.saveDeviceId(deviceId)
                store.saveDeviceSecret(deviceSecret)
                licenseToken = trimmedToken
                lastMessage = "License activated"
                await validateNow()
                return true
            } else {
                let message = response.error ?? "Activation failed"
                status = .invalid(reason: message)
                lastMessage = message
                return false
            }
        } catch {
            status = .error(message: error.localizedDescription)
            lastMessage = error.localizedDescription
            return false
        }
    }

    func validateNow() async {
        guard let token = currentToken else {
            status = .unlicensed
            return
        }

        guard let deviceAuth = currentDeviceAuth else {
            status = .invalid(reason: "Activate on this Mac first")
            return
        }

        status = .checking
        lastMessage = nil

        do {
            let response = try await client.validate(token: token, deviceAuth: deviceAuth)
            if response.valid {
                let info = response.license
                let parsedExpiry = parseDate(info?.expiresAt)
                updateCache(
                    type: info?.type,
                    status: info?.status,
                    expiresAt: parsedExpiry,
                    isValid: true
                )
                status = .active
            } else {
                updateCache(type: nil, status: nil, expiresAt: nil, isValid: false)
                status = .invalid(reason: response.error ?? "License is not valid")
            }
        } catch {
            handleValidationFailure(error)
        }
    }

    func resendLicense(to email: String) async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty else {
            lastMessage = "Enter an email address"
            return
        }

        do {
            let response = try await client.resend(email: trimmedEmail)
            if response.success == true {
                lastMessage = "License email sent"
            } else {
                lastMessage = response.error ?? "Unable to resend"
            }
        } catch {
            lastMessage = error.localizedDescription
        }
    }

    // MARK: - State & Cache

    func validateIfNeeded() async {
        guard let cache = store.loadCache() else {
            return
        }

        let now = Date()
        if now.timeIntervalSince(cache.lastValidatedAt) < validationInterval {
            applyCache(cache)
            return
        }

        await validateNow()
    }

    private func handleValidationFailure(_ error: Error) {
        logger.error("License validation failed: \(error.localizedDescription)")

        if deviceAuthService.isInvalidDeviceAuth(error),
           let token = currentToken {
            Task {
                _ = await deviceAuthService.refreshDeviceAuth(token: token, deviceName: Host.current().localizedName ?? "Mac")
            }
        } else if let cache = store.loadCache(),
                  cache.isValid,
                  let daysLeft = offlineGraceDaysLeft(from: cache.lastValidatedAt) {
            applyCache(cache)
            status = .offlineGrace(daysLeft: daysLeft)
            lastMessage = "Offline grace period"
            return
        }

        status = .error(message: error.localizedDescription)
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

    private func scheduleValidationTimer() {
        validationTask?.cancel()
        validationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.validationInterval ?? 86400))
                guard !Task.isCancelled else { break }
                await self?.validateNow()
            }
        }
    }

    func offlineGraceDaysLeft(from date: Date) -> Int? {
        let elapsed = Date().timeIntervalSince(date)
        let remaining = (Double(offlineGraceDays) * 86400) - elapsed
        guard remaining > 0 else { return nil }
        return Int(ceil(remaining / 86400))
    }
}
