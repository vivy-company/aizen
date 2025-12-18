//
//  SpotlightPalette.swift
//  aizen
//
//  Shared Spotlight-style palette chrome used by Cmd+P / Cmd+K panels.
//

import SwiftUI
import Combine

@MainActor
final class PaletteInteractionState: ObservableObject {
    @Published var allowHoverSelection: Bool = true

    func didUseKeyboard() {
        allowHoverSelection = false
    }

    func didMoveMouse() {
        allowHoverSelection = true
    }
}

struct LiquidGlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 24
    var shadowOpacity: Double = 0.45
    var tint: Color = .black.opacity(0.22)
    var sheenOpacity: Double = 0.22
    var scrimOpacity: Double = 0.12
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content()
            .background { glassBackground(shape: shape) }
            .clipShape(shape)
        .overlay {
            shape.strokeBorder(.white.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(shadowOpacity), radius: 40, x: 0, y: 22)
    }

    @ViewBuilder
    private func glassBackground(shape: RoundedRectangle) -> some View {
        if #available(macOS 26.0, *) {
            ZStack {
                GlassEffectContainer {
                    shape
                        .fill(.white.opacity(0.001))
                        .glassEffect(.regular.tint(tint), in: shape)
                }
                .allowsHitTesting(false)

                shape
                    .fill(.black.opacity(scrimOpacity))
                    .allowsHitTesting(false)

                if sheenOpacity > 0 {
                    LinearGradient(
                        colors: [
                            .white.opacity(0.28 * sheenOpacity),
                            .white.opacity(0.10 * sheenOpacity),
                            .clear,
                            .white.opacity(0.08 * sheenOpacity),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
                    .clipShape(shape)
                }
            }
        } else {
            shape.fill(.regularMaterial)
        }
    }
}

struct KeyCap: View {
    let text: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

        Group {
            if #available(macOS 26.0, *) {
                GlassEffectContainer {
                    Text(text)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .glassEffect(.regular, in: shape)
                }
            } else {
                Text(text)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.thinMaterial, in: shape)
            }
        }
        .overlay {
            shape.strokeBorder(.white.opacity(0.10), lineWidth: 1)
        }
        .accessibilityLabel(Text(text))
    }
}

struct SpotlightSearchField<Trailing: View>: View {
    let placeholder: LocalizedStringKey
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    var onSubmit: (() -> Void)?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .medium))
                .focused($isFocused)
                .disableAutocorrection(true)
                .onSubmit {
                    onSubmit?()
                }

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.9))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear"))
            }

            trailing()
        }
    }
}
