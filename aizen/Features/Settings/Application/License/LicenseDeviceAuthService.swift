//
//  LicenseDeviceAuthService.swift
//  aizen
//
//  Created by OpenAI Codex on 04.04.26.
//

import CryptoKit
import Darwin
import Foundation
import IOKit
import os.log

struct LicenseDeviceAuthService {
    let store: LicenseStore
    let client: LicenseClient
    let logger: Logger

    func getOrCreateDeviceFingerprint() -> String {
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

    func isInvalidDeviceAuth(_ error: Error) -> Bool {
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

    func refreshDeviceAuth(token: String, deviceName: String) async -> Bool {
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

    private func sha256Hex(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func ioRegistryValue(key: String) -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
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
