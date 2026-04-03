import AppKit
import SwiftUI

extension AizenProPlansSheet {
    var proCard: some View {
        planCard(
            title: "Pro",
            subtitle: "",
            price: proPriceLabel,
            features: ["Support continued development", "Priority support", "Future exclusive features"],
            isSelected: selectedPlan == .pro
        ) {
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

    var lifetimeCard: some View {
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

    func planCard(
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
    func planCard<Top: View, Bottom: View>(
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

    var proURL: URL {
        switch selectedBilling {
        case .monthly:
            return URL(string: "https://buy.stripe.com/dRmdR1dOI9eHfyW0LA3Ru00")!
        case .yearly:
            return URL(string: "https://buy.stripe.com/eVqfZ9bGAduXaeC9i63Ru02")!
        }
    }

    var lifetimeURL: URL {
        URL(string: "https://buy.stripe.com/8x23cn7qk2QjgD0gKy3Ru01")!
    }

    var proPriceLabel: String {
        switch selectedBilling {
        case .monthly:
            return "$5.99 / mo"
        case .yearly:
            return "$59 / yr"
        }
    }
}
