//
//  ACPContentViews.swift
//  aizen
//
//  Shared views for rendering ACP content blocks
//

import Foundation
import SwiftUI
import VVCode

// MARK: - Attachment Glass Card

struct AttachmentGlassCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat = 12
    @ViewBuilder var content: () -> Content

    private var strokeColor: Color {
        colorScheme == .dark ? .white.opacity(0.12) : .black.opacity(0.08)
    }

    private var tintColor: Color {
        colorScheme == .dark ? .black.opacity(0.18) : .white.opacity(0.5)
    }

    private var scrimColor: Color {
        colorScheme == .dark ? .black.opacity(0.08) : .white.opacity(0.04)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content()
            .background { glassBackground(shape: shape) }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(strokeColor, lineWidth: 0.5)
            }
    }

    @ViewBuilder
    private func glassBackground(shape: RoundedRectangle) -> some View {
        if #available(macOS 26.0, *) {
            ZStack {
                GlassEffectContainer {
                    shape
                        .fill(.white.opacity(0.001))
                        .glassEffect(.regular.tint(tintColor), in: shape)
                }
                .allowsHitTesting(false)

                shape
                    .fill(scrimColor)
                    .allowsHitTesting(false)
            }
        } else {
            shape.fill(.ultraThinMaterial)
        }
    }
}

// MARK: - User Attachment Chip (for displaying file attachments in user messages)

struct UserAttachmentChip: View {
    let name: String
    let uri: String

    private var filePath: String {
        if uri.hasPrefix("file://") {
            return URL(string: uri)?.path ?? uri
        }
        return uri
    }

    var body: some View {
        AttachmentChip(
            title: name,
            icon: AnyView(FileIconView(path: filePath, size: 16)),
            detailView: nil,
            style: AttachmentChip.Style(showsDelete: false, showsHoverFade: false)
        )
    }
}
