//
//  LicenseStateStore+DeviceActions.swift
//  aizen
//

import AppKit
import Foundation

extension LicenseStateStore {
    func openBillingPortal(returnUrl: String) async {
        await openBillingPortalInternal(returnUrl: returnUrl, allowReauth: true)
    }

    func deactivateThisMac() async {
        await deactivateThisMacInternal(allowReauth: true)
    }

    func clearDeviceCredentials() {
        store.clearDeviceId()
        store.clearDeviceSecret()
        store.clearCache()
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
}
