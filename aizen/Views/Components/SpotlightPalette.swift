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
    @Environment(\.colorScheme) private var colorScheme

    var cornerRadius: CGFloat = 24
    var shadowOpacity: Double = 0.45
    var sheenOpacity: Double = 0.22
    var scrimOpacity: Double = 0.12
    @ViewBuilder var content: () -> Content

    private var tint: Color {
        colorScheme == .dark ? .black.opacity(0.22) : .white.opacity(0.6)
    }

    private var strokeColor: Color {
        colorScheme == .dark ? .white.opacity(0.14) : .black.opacity(0.08)
    }

    private var scrimColor: Color {
        colorScheme == .dark ? .black.opacity(scrimOpacity) : .white.opacity(scrimOpacity * 0.5)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content()
            .background { glassBackground(shape: shape) }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(strokeColor, lineWidth: 1)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? shadowOpacity : shadowOpacity * 0.3), radius: 40, x: 0, y: 22)
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
                    .fill(scrimColor)
                    .allowsHitTesting(false)

                if sheenOpacity > 0 && colorScheme == .dark {
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
    @Environment(\.colorScheme) private var colorScheme
    let text: String

    private var strokeColor: Color {
        colorScheme == .dark ? .white.opacity(0.10) : .black.opacity(0.08)
    }

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
            shape.strokeBorder(strokeColor, lineWidth: 1)
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
        SearchField(
            placeholder: placeholder,
            text: $text,
            spacing: 12,
            iconSize: 16,
            iconWeight: .semibold,
            iconColor: .secondary,
            textFont: .system(size: 22, weight: .medium),
            clearButtonSize: 15,
            clearButtonWeight: .semibold,
            clearButtonOpacity: 0.9,
            onSubmit: onSubmit,
            isFocused: $isFocused,
            disableAutocorrection: true,
            trailing: trailing
        )
    }
}
