import SwiftUI

extension AizenProPlansSheet {
    var header: some View {
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

    var footerNotice: some View {
        Text("By subscribing you agree to our privacy policy and refund policy.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}
