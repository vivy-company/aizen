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
    @State private var showingPlans = false

    var body: some View {
        VStack(spacing: 12) {
            if !licenseManager.hasActivePlan {
                upgradeBanner
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
            }

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
        }
        .toolbar {
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

    private var licenseManagerHasDevice: Bool {
        licenseManager.hasDeviceCredentials
    }

    private var statusBadge: some View {
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

    private var upgradeBanner: some View {
        Button {
            showingPlans = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(
                            colors: [Color.pink, Color.orange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 36, height: 36)
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Upgrade to Aizen Pro")
                        .font(.headline)
                    Text("Priority support included.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("View Plans")
                    .font(.callout)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                    )
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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
                action: dismiss,
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
