import SwiftUI

struct ChatProcessingIndicator: View {
    let currentThought: String?
    let renderInlineMarkdown: (String) -> AttributedString

    @State private var cachedThoughtText: String?
    @State private var cachedThoughtRendered: AttributedString = AttributedString("")

    var body: some View {
        HStack(spacing: 8) {
            ChatProcessingSpinner()

            if cachedThoughtText != nil {
                Text(cachedThoughtRendered)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .modifier(
                        ShimmerEffect(
                            bandSize: 0.38,
                            duration: 2.2,
                            baseOpacity: 0.08,
                            highlightOpacity: 1.0
                        )
                    )
            } else {
                Text("chat.agent.thinking", bundle: .main)
                    .font(.callout)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                    .modifier(
                        ShimmerEffect(
                            bandSize: 0.38,
                            duration: 2.2,
                            baseOpacity: 0.08,
                            highlightOpacity: 1.0
                        )
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            updateCachedThought(currentThought)
        }
        .task(id: currentThought) {
            updateCachedThought(currentThought)
        }
    }

    private func updateCachedThought(_ thought: String?) {
        guard thought != cachedThoughtText else { return }
        cachedThoughtText = thought
        if let thought {
            cachedThoughtRendered = renderInlineMarkdown(thought)
        } else {
            cachedThoughtRendered = AttributedString("")
        }
    }
}

private struct ChatProcessingSpinner: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .trim(from: 0.2, to: 0.9)
            .stroke(
                Color.secondary.opacity(0.85),
                style: StrokeStyle(lineWidth: 1.8, lineCap: .round)
            )
            .frame(width: 14, height: 14)
            .rotationEffect(.degrees(isAnimating ? 360 : 0))
            .animation(
                reduceMotion ? .none : .linear(duration: 0.9).repeatForever(autoreverses: false),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
            .onDisappear {
                isAnimating = false
            }
    }
}
