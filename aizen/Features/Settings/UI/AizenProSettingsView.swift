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

private struct AizenProPlansSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlan: PlanType = .pro
    @State private var selectedBilling: BillingCycle = .monthly

    private enum PlanType {
        case pro
        case lifetime
    }

    private enum BillingCycle {
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

    private var proCard: some View {
        planCard(
            title: "Pro",
            subtitle: "",
            price: proPriceLabel,
            features: ["Support continued development", "Priority support", "Future exclusive features"],
            isSelected: selectedPlan == .pro
        ) { // topContent
            GlassSegmentedTabs(
                options: [
                    GlassSegmentedTabs.Option(title: "Monthly", value: .monthly),
                    GlassSegmentedTabs.Option(title: "Yearly", value: .yearly, badge: "20% off")
                ],
                selection: $selectedBilling
            )
        } bottomContent: {
            GlassPrimaryButton(title: "Subscribe") {
                NSWorkspace.shared.open(proURL)
            }
        }
        .onTapGesture {
            selectedPlan = .pro
        }
    }

    private var lifetimeCard: some View {
        planCard(
            title: "Lifetime",
            subtitle: "One-time purchase",
            price: "$179",
            features: ["Support continued development", "Priority support forever", "Future exclusive features"],
            isSelected: selectedPlan == .lifetime
        ) {
            EmptyView()
        } bottomContent: {
            GlassPrimaryButton(title: "Purchase") {
                NSWorkspace.shared.open(lifetimeURL)
            }
        }
        .onTapGesture {
            selectedPlan = .lifetime
        }
    }

    private func planCard(
        title: String,
        subtitle: String,
        price: String,
        features: [String],
        isSelected: Bool
    ) -> some View {
        planCard(
            title: title,
            subtitle: subtitle,
            price: price,
            features: features,
            isSelected: isSelected,
            topContent: { EmptyView() },
            bottomContent: { EmptyView() }
        )
    }

    @ViewBuilder
    private func planCard<Top: View, Bottom: View>(
        title: String,
        subtitle: String,
        price: String,
        features: [String],
        isSelected: Bool,
        @ViewBuilder topContent: () -> Top,
        @ViewBuilder bottomContent: () -> Bottom
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Text(price)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
            }

            topContent()

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(features, id: \.self) { feature in
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(feature)
                            .font(.callout)
                    }
                }
            }

            Spacer()

            bottomContent()
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 220)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(isSelected ? 0.06 : 0.04))
                .modifier(GlassBackground(cornerRadius: 18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(isSelected ? 0.16 : 0.08), lineWidth: 1)
        )
    }

    private var proURL: URL {
        switch selectedBilling {
        case .monthly:
            return URL(string: "https://buy.stripe.com/dRmdR1dOI9eHfyW0LA3Ru00")!
        case .yearly:
            return URL(string: "https://buy.stripe.com/eVqfZ9bGAduXaeC9i63Ru02")!
        }
    }

    private var lifetimeURL: URL {
        URL(string: "https://buy.stripe.com/8x23cn7qk2QjgD0gKy3Ru01")!
    }

    private var proPriceLabel: String {
        switch selectedBilling {
        case .monthly:
            return "$5.99 / mo"
        case .yearly:
            return "$59 / yr"
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

private struct GlassPrimaryButton: View {
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

private struct GlassSegmentedTabs<Value: Hashable>: View {
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

private struct GlassBackground: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            content
        }
    }
}
