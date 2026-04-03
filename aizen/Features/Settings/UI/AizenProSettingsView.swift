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

struct GlassPrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.12))
                .modifier(GlassBackground(cornerRadius: 12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }
}

struct GlassSegmentedTabs<Value: Hashable>: View {
    struct Option: Identifiable {
        let id = UUID()
        let title: String
        let value: Value
        let badge: String?

        init(title: String, value: Value, badge: String? = nil) {
            self.title = title
            self.value = value
            self.badge = badge
        }
    }

    let options: [Option]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options) { option in
                Button {
                    selection = option.value
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Text(option.title)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(selection == option.value ? Color.white.opacity(0.16) : Color.clear)
                            )

                        if let badge = option.badge {
                            Text(badge)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .foregroundStyle(.white)
                                .background(
                                    Capsule()
                                        .fill(LinearGradient(
                                            colors: [Color.orange, Color.pink],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ))
                                )
                                .offset(x: 8, y: -8)
                        }
                    }
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .modifier(GlassBackground(cornerRadius: 12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .frame(maxWidth: .infinity)
    }
}

struct GlassBackground: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            content
        }
    }
}
