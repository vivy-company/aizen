import Foundation
import SwiftUI

extension AizenProSettingsView {
    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if licenseManager.hasActivePlan {
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
            } else {
                Button {
                    showingPlans = true
                } label: {
                    Label("Upgrade", systemImage: "sparkles")
                }
                .labelStyle(.titleAndIcon)
            }
        }
    }

    func handlePendingDeepLink() {
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
