//
//  LicenseDeepLinkSheet.swift
//  aizen
//
//  Deep link activation sheet for Aizen Pro
//

import SwiftUI

struct LicenseDeepLinkSheet: View {
    @ObservedObject var licenseManager: LicenseManager
    let onOpenSettings: () -> Void

    @State private var state: ActivationState = .idle
    @State private var token: String = ""
    @State private var autoActivate = false

    @Environment(\.dismiss) private var dismiss

    enum ActivationState: Equatable {
        case idle
        case ready
        case activating
        case success
        case failure(String)
    }

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.pink, Color.orange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 42, height: 42)
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
            }

            Text(titleText)
                .font(.title3)
                .fontWeight(.semibold)

            Text(subtitleText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if state == .activating {
                ProgressView()
                    .progressViewStyle(.circular)
            }

            HStack(spacing: 10) {
                Button("Open Settings") {
                    onOpenSettings()
                }

                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 360)
        .onAppear {
            start()
        }
    }

    private var titleText: String {
        switch state {
        case .success:
            return "Aizen Pro Activated"
        case .failure:
            return "Activation Failed"
        case .activating:
            return "Activating Aizen Pro"
        case .ready:
            return "Ready to Activate"
        case .idle:
            return "Aizen Pro"
        }
    }

    private var subtitleText: String {
        switch state {
        case .success:
            return "Your license is active on this Mac."
        case .failure(let message):
            return message
        case .activating:
            return "Validating your license and registering this device."
        case .ready:
            return "Tap Activate in Settings to finish activation."
        case .idle:
            return "Preparing activation."
        }
    }

    private func start() {
        guard let pending = licenseManager.consumePendingDeepLink() else {
            if licenseManager.hasDeviceCredentials {
                state = .success
            } else {
                state = .failure("Missing activation data")
            }
            return
        }

        token = pending.token ?? ""
        autoActivate = pending.autoActivate

        if autoActivate || (!token.isEmpty && !licenseManager.hasDeviceCredentials) {
            activate()
        } else {
            state = licenseManager.hasDeviceCredentials ? .success : .ready
        }
    }

    private func activate() {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state = .failure("Missing license key")
            return
        }

        state = .activating
        let name = Host.current().localizedName ?? "Mac"
        Task {
            let success = await licenseManager.activate(token: token, deviceName: name)
            if success {
                state = .success
            } else {
                let message = activationErrorMessage()
                state = .failure(message)
            }
        }
    }

    private func activationErrorMessage() -> String {
        switch licenseManager.status {
        case .invalid(let reason):
            return reason
        case .error(let message):
            return message
        default:
            return "Activation failed."
        }
    }
}
