import ACP
import Foundation
import SwiftUI

extension AizenProSettingsView {
    @ViewBuilder
    var statusSection: some View {
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
                    Text(DateFormatters.mediumDateTime.string(from: expiresAt))
                        .foregroundStyle(.secondary)
                }
            }

            if let validatedAt = licenseManager.lastValidatedAt {
                HStack {
                    Text("Last Checked")
                    Spacer()
                    Text(DateFormatters.mediumDateTime.string(from: validatedAt))
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
    }

    @ViewBuilder
    var activateSection: some View {
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
    }

    @ViewBuilder
    var billingSection: some View {
        Section("Billing") {
            Button("Resend License Email") {
                showingResendPrompt = true
            }
        }
    }

    @ViewBuilder
    var deviceSection: some View {
        Section("Device") {
            Button("Deactivate this Mac", role: .destructive) {
                Task { await licenseManager.deactivateThisMac() }
            }
            .disabled(!licenseManagerHasDevice)
        }
    }

    var licenseManagerHasDevice: Bool {
        licenseManager.hasDeviceCredentials
    }

    var statusBadge: some View {
        let (title, color) = statusPresentation(for: licenseManager.status)
        return PillBadge(
            text: title,
            color: color,
            textColor: .white,
            font: .caption,
            horizontalPadding: 8,
            verticalPadding: 4,
            backgroundOpacity: 1
        )
    }

    func statusPresentation(for status: LicenseStateStore.Status) -> (String, Color) {
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
}
