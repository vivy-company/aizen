import SwiftUI

struct AizenBellBorderOverlay: View {
    let bell: Bool

    var body: some View {
        Rectangle()
            .strokeBorder(
                Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.5),
                lineWidth: 3
            )
            .allowsHitTesting(false)
            .opacity(bell ? 1.0 : 0.0)
            .animation(.easeInOut(duration: 0.3), value: bell)
    }
}

struct AizenHighlightOverlay: View {
    let highlighted: Bool

    @State private var borderPulse = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.accentColor.opacity(0.12),
                            Color.accentColor.opacity(0.03),
                            Color.clear,
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: 2000
                    )
                )

            Rectangle()
                .strokeBorder(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.accentColor.opacity(0.8),
                            Color.accentColor.opacity(0.5),
                            Color.accentColor.opacity(0.8),
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: borderPulse ? 4 : 2
                )
                .shadow(color: Color.accentColor.opacity(borderPulse ? 0.8 : 0.6), radius: borderPulse ? 12 : 8)
                .shadow(color: Color.accentColor.opacity(borderPulse ? 0.5 : 0.3), radius: borderPulse ? 24 : 16)
        }
        .allowsHitTesting(false)
        .opacity(highlighted ? 1.0 : 0.0)
        .animation(.easeOut(duration: 0.4), value: highlighted)
        .task(id: highlighted) {
            if highlighted {
                withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true)) {
                    borderPulse = true
                }
            } else {
                withAnimation(.easeOut(duration: 0.4)) {
                    borderPulse = false
                }
            }
        }
    }
}

struct AizenSurfaceMessageView: View {
    let title: String
    let message: String

    var body: some View {
        HStack {
            Image("AppIconImage")
                .resizable()
                .scaledToFit()
                .frame(width: 128, height: 128)

            VStack(alignment: .leading) {
                Text(title)
                    .font(.title)
                Text(message)
                    .frame(maxWidth: 350)
            }
        }
        .padding()
    }
}
