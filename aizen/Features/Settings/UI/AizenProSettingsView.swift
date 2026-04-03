//
//  AizenProSettingsView.swift
//  aizen
//
//  Settings view for Aizen Pro license
//

import Foundation
import SwiftUI

struct AizenProSettingsView: View {
    @ObservedObject var licenseManager: LicenseStateStore

    @State var tokenInput: String = ""
    @State var showingResendPrompt = false
    @State var resendEmail = ""
    @State var showingPlans = false

    var body: some View {
        VStack(spacing: 12) {
            if !licenseManager.hasActivePlan {
                upgradeBanner
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
            }

            Form {
                statusSection
                activateSection
                billingSection
                deviceSection
            }
            .formStyle(.grouped)
        }
        .settingsSurface()
        .toolbar {
            toolbarContent
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
        .sheet(isPresented: $showingPlans) {
            AizenProPlansSheet()
        }
        .onAppear {
            handlePendingDeepLink()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openLicenseDeepLink)) { _ in
            handlePendingDeepLink()
        }
    }

}

struct AizenProPlansSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var selectedPlan: PlanType = .pro
    @State var selectedBilling: BillingCycle = .monthly

    enum PlanType {
        case pro
        case lifetime
    }

    enum BillingCycle {
        case monthly
        case yearly
    }

    var body: some View {
        VStack(spacing: 18) {
            header

            HStack(spacing: 18) {
                proCard
                lifetimeCard
            }
            footerNotice
        }
        .padding(28)
        .frame(width: 640, height: 420)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color.pink, Color.orange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 44, height: 44)
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Aizen Pro")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Priority support included.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            CircleIconButton(
                systemName: "xmark",
                action: { dismiss() },
                size: 12,
                weight: .semibold,
                foreground: .secondary,
                backgroundColor: .white,
                backgroundOpacity: 0.06,
                padding: 8
            )
        }
    }

    private var footerNotice: some View {
        Text("By subscribing you agree to our privacy policy and refund policy.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}
