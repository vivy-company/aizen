//
//  LicenseStateStore+Actions.swift
//  aizen
//

import Foundation

extension LicenseStateStore {
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
}
