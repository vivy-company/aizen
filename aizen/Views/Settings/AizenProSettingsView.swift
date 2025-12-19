//
//  AizenProSettingsView.swift
//  aizen
//
//  Settings view for Aizen Pro license
//

import SwiftUI
import Foundation

struct AizenProSettingsView: View {
    @ObservedObject var licenseManager: LicenseManager

    @State private var tokenInput: String = ""
    @State private var showingResendPrompt = false
    @State private var resendEmail = ""

    var body: some View {
        Form {
            Section("Status") {
                HStack {
                    Text("License")
                    Spacer()
                    statusBadge
                }

                if let type = licenseManager.licenseType {
                    HStack {
                        Text("Plan")
                        Spacer()
                        Text(type.capitalized)
                            .foregroundStyle(.secondary)
                    }
                }

                if let expiresAt = licenseManager.expiresAt {
                    HStack {
                        Text("Expires")
                        Spacer()
                        Text(dateFormatter.string(from: expiresAt))
                            .foregroundStyle(.secondary)
                    }
                }

                if let validatedAt = licenseManager.lastValidatedAt {
                    HStack {
                        Text("Last Checked")
                        Spacer()
                        Text(dateFormatter.string(from: validatedAt))
                            .foregroundStyle(.secondary)
                    }
                }

                if let message = licenseManager.lastMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if case .invalid(let reason) = licenseManager.status {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if case .error(let message) = licenseManager.status {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Activate") {
                SecureField("License Key", text: $tokenInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                HStack {
                    Button(licenseManager.licenseToken.isEmpty ? "Activate" : "Update") {
                        let name = Host.current().localizedName ?? "Mac"
                        Task {
                            await licenseManager.activate(token: tokenInput, deviceName: name)
                        }
                    }
                    .disabled(tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       !licenseManager.licenseToken.isEmpty {
                        Button("Re-activate") {
                            let name = Host.current().localizedName ?? "Mac"
                            Task {
                                await licenseManager.activate(token: licenseManager.licenseToken, deviceName: name)
                            }
                        }
                    }
                }
            }

            Section("Billing") {
                Button("Resend License Email") {
                    showingResendPrompt = true
                }
            }

            Section("Device") {
                Button("Deactivate this Mac", role: .destructive) {
                    Task { await licenseManager.deactivateThisMac() }
                }
                .disabled(!licenseManagerHasDevice)
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await licenseManager.validateNow() }
                } label: {
                    Label("Validate Now", systemImage: "checkmark.seal")
                }
                .labelStyle(.titleAndIcon)
                .disabled(!licenseManagerHasDevice)

                Button {
                    Task {
                        await licenseManager.openBillingPortal(returnUrl: "aizen://settings")
                    }
                } label: {
                    Label("Manage Billing", systemImage: "creditcard")
                }
                .labelStyle(.titleAndIcon)
                .disabled(!licenseManagerHasDevice)
            }
        }
        .alert("Resend License Email", isPresented: $showingResendPrompt) {
            TextField("Email", text: $resendEmail)
            Button("Send") {
                Task {
                    await licenseManager.resendLicense(to: resendEmail)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("We’ll resend your license to this email address.")
        }
        .onAppear {
            handlePendingDeepLink()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openLicenseDeepLink)) { _ in
            handlePendingDeepLink()
        }
    }

    private var licenseManagerHasDevice: Bool {
        licenseManager.hasDeviceCredentials
    }

    private var statusBadge: some View {
        let (title, color) = statusPresentation(for: licenseManager.status)
        return Text(title)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(color))
            .foregroundStyle(.white)
    }

    private func statusPresentation(for status: LicenseManager.Status) -> (String, Color) {
        switch status {
        case .unlicensed:
            return ("Not Activated", .gray)
        case .checking:
            return ("Checking", .orange)
        case .active:
            return ("Active", .green)
        case .expired:
            return ("Expired", .red)
        case .offlineGrace(let daysLeft):
            return ("Offline \(daysLeft)d", .yellow)
        case .invalid:
            return ("Invalid", .red)
        case .error:
            return ("Error", .red)
        }
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }

    private func handlePendingDeepLink() {
        guard let pending = licenseManager.consumePendingDeepLink() else { return }

        if let token = pending.token, !token.isEmpty {
            tokenInput = token
        }

        if pending.autoActivate {
            let name = Host.current().localizedName ?? "Mac"
            Task {
                await licenseManager.activate(token: tokenInput, deviceName: name)
            }
        }
    }
}
