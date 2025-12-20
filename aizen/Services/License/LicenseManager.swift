//
//  LicenseManager.swift
//  aizen
//
//  Client-side license state management
//

import Foundation
import AppKit
import CryptoKit
import IOKit
import os.log
import Darwin
import Combine

@MainActor
final class LicenseManager: ObservableObject {
    static let shared = LicenseManager()

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

    private var validationTimer: Timer?
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

        let fingerprint = getOrCreateDeviceFingerprint()

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
               isInvalidDeviceAuth(error),
               await refreshDeviceAuth(token: token, deviceName: Host.current().localizedName ?? "Mac") {
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
            if allowReauth && isInvalidDeviceAuth(error),
               await refreshDeviceAuth(token: token, deviceName: Host.current().localizedName ?? "Mac") {
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

        if isInvalidDeviceAuth(error),
           let token = currentToken {
            Task {
                _ = await refreshDeviceAuth(token: token, deviceName: Host.current().localizedName ?? "Mac")
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

    private func clearDeviceCredentials() {
        store.clearDeviceId()
        store.clearDeviceSecret()
        store.clearCache()
    }

    private func scheduleValidationTimer() {
        validationTimer?.invalidate()
        validationTimer = Timer.scheduledTimer(withTimeInterval: validationInterval, repeats: true) { [weak self] _ in
            Task { await self?.validateNow() }
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
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }

    private func getOrCreateDeviceFingerprint() -> String {
        if let stored = store.loadDeviceFingerprint() {
            return stored
        }

        let raw = [
            ioRegistryValue(key: "IOPlatformUUID"),
            ioRegistryValue(key: "IOPlatformSerialNumber"),
            hardwareModel()
        ]
        .compactMap { $0 }
        .joined(separator: "-")

        let source = raw.isEmpty ? UUID().uuidString : raw
        let fingerprint = sha256Hex(source)
        store.saveDeviceFingerprint(fingerprint)
        return fingerprint
    }

    private func sha256Hex(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func isInvalidDeviceAuth(_ error: Error) -> Bool {
        if let apiError = error as? LicenseAPIError {
            switch apiError {
            case .server(let message):
                return message.localizedCaseInsensitiveContains("invalid device authentication")
            default:
                return false
            }
        }

        return error.localizedDescription.localizedCaseInsensitiveContains("invalid device authentication")
    }

    private func refreshDeviceAuth(token: String, deviceName: String) async -> Bool {
        let fingerprint = getOrCreateDeviceFingerprint()
        do {
            let response = try await client.activate(
                token: token,
                deviceFingerprint: fingerprint,
                deviceName: deviceName
            )

            if response.success == true,
               let deviceId = response.deviceId,
               let deviceSecret = response.deviceSecret {
                store.saveToken(token)
                store.saveDeviceId(deviceId)
                store.saveDeviceSecret(deviceSecret)
                return true
            }
        } catch {
            logger.error("Device re-auth failed: \(error.localizedDescription)")
        }

        return false
    }

    private func ioRegistryValue(key: String) -> String? {
        let service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        guard let cfValue = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }

        return (cfValue.takeRetainedValue() as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func hardwareModel() -> String? {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        let value = String(cString: buffer)
        return value.isEmpty ? nil : value
    }
}
