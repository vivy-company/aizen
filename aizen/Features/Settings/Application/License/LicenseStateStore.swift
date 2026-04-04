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

    @Published private(set) var status: Status = .unlicensed
    @Published private(set) var licenseType: String?
    @Published private(set) var licenseStatus: String?
    @Published private(set) var expiresAt: Date?
    @Published private(set) var lastValidatedAt: Date?
    @Published private(set) var lastMessage: String?

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

    private let store = LicenseStore()

    private let client = LicenseClient()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "win.aizen.app", category: "License")

    private var validationTask: Task<Void, Never>?
    private let validationInterval: TimeInterval = 24 * 60 * 60
    private let offlineGraceDays = 7

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

    func openBillingPortal(returnUrl: String) async {
        await openBillingPortalInternal(returnUrl: returnUrl, allowReauth: true)
    }

    private func openBillingPortalInternal(returnUrl: String, allowReauth: Bool) async {
        guard let token = currentToken,
              let deviceAuth = currentDeviceAuth else {
            status = .invalid(reason: "Activate on this Mac first")
            return
        }

        do {
            let response = try await client.portal(token: token, deviceAuth: deviceAuth, returnUrl: returnUrl)
            if let urlString = response.url, let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            } else {
                lastMessage = response.error ?? "Unable to open billing portal"
            }
        } catch {
            if allowReauth,
               deviceAuthService.isInvalidDeviceAuth(error),
               await deviceAuthService.refreshDeviceAuth(token: token, deviceName: Host.current().localizedName ?? "Mac") {
                await openBillingPortalInternal(returnUrl: returnUrl, allowReauth: false)
            } else {
                lastMessage = error.localizedDescription
            }
        }
    }

    func deactivateThisMac() async {
        await deactivateThisMacInternal(allowReauth: true)
    }

    private func deactivateThisMacInternal(allowReauth: Bool) async {
        guard let token = currentToken else {
            status = .unlicensed
            return
        }

        do {
            let response = try await client.deactivate(
                token: token,
                deviceAuth: currentDeviceAuth
            )
            if response.success == true {
                clearDeviceCredentials()
                lastMessage = "Device deactivated"
                status = .unlicensed
            } else {
                lastMessage = response.error ?? "Unable to deactivate"
            }
        } catch {
            if allowReauth && deviceAuthService.isInvalidDeviceAuth(error),
               await deviceAuthService.refreshDeviceAuth(token: token, deviceName: Host.current().localizedName ?? "Mac") {
                await deactivateThisMacInternal(allowReauth: false)
            } else {
                lastMessage = error.localizedDescription
            }
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

    private func loadFromStore() {
        licenseToken = store.loadToken() ?? ""
        if let cache = store.loadCache() {
            applyCache(cache)
        } else if licenseToken.isEmpty {
            status = .unlicensed
        }
    }

    private func updateCache(type: String?, status: String?, expiresAt: Date?, isValid: Bool) {
        let cache = LicenseCache(
            type: type,
            status: status,
            expiresAt: expiresAt,
            isValid: isValid,
            lastValidatedAt: Date()
        )
        store.saveCache(cache)
        applyCache(cache)
    }

    private func applyCache(_ cache: LicenseCache) {
        licenseType = cache.type
        licenseStatus = cache.status
        expiresAt = cache.expiresAt
        lastValidatedAt = cache.lastValidatedAt

        if cache.isValid {
            if let expiresAt, expiresAt < Date() {
                status = .expired
            } else {
                status = .active
            }
        } else if licenseToken.isEmpty {
            status = .unlicensed
        } else {
            status = .expired
        }
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

    private var currentToken: String? {
        let trimmed = licenseToken.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var currentDeviceAuth: LicenseClient.DeviceAuth? {
        guard let deviceId = store.loadDeviceId(),
              let deviceSecret = store.loadDeviceSecret() else {
            return nil
        }
        return LicenseClient.DeviceAuth(deviceId: deviceId, deviceSecret: deviceSecret)
    }

    private var deviceAuthService: LicenseDeviceAuthService {
        LicenseDeviceAuthService(store: store, client: client, logger: logger)
    }

    private func clearDeviceCredentials() {
        store.clearDeviceId()
        store.clearDeviceSecret()
        store.clearCache()
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

    private func offlineGraceDaysLeft(from date: Date) -> Int? {
        let elapsed = Date().timeIntervalSince(date)
        let remaining = (Double(offlineGraceDays) * 86400) - elapsed
        guard remaining > 0 else { return nil }
        return Int(ceil(remaining / 86400))
    }

    private func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        return ISO8601DateParser.shared.parse(string)
    }
}
