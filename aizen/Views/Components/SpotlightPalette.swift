//
//  SpotlightPalette.swift
//  aizen
//
//  Shared Spotlight-style palette chrome used by Cmd+P / Cmd+K panels.
//

import SwiftUI

struct LiquidGlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 24
    var shadowOpacity: Double = 0.45
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        Group {
            if #available(macOS 26.0, *) {
                GlassEffectContainer {
                    content()
                        .glassEffect(.regular.tint(.black.opacity(0.22)), in: shape)
                }
            } else {
                content()
                    .background(.regularMaterial, in: shape)
            }
        }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(shadowOpacity), radius: 40, x: 0, y: 22)
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
                .textInputAutocapitalization(.never)
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

