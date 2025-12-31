//
//  AttachmentChip.swift
//  aizen
//
//  Shared attachment chip for chat UI
//

import SwiftUI

struct AttachmentChip: View {
    struct Style {
        var cornerRadius: CGFloat = 10
        var paddingHorizontal: CGFloat = 10
        var paddingVertical: CGFloat = 6
        var showsDelete: Bool = true
        var showsHoverFade: Bool = true
    }

    let label: AnyView
    let detailView: AnyView?
    var style: Style = Style()
    var onDelete: (() -> Void)?

    @State private var showingDetail = false
    @State private var isHovering = false

    var body: some View {
        AttachmentGlassCard(cornerRadius: style.cornerRadius) {
            HStack(spacing: 6) {
                if hasDetailView {
                    Button {
                        showingDetail = true
                    } label: {
                        label
                    }
                    .buttonStyle(.plain)
                } else {
                    label
                }

                if style.showsDelete, let onDelete {
                    DetailCloseButton(action: onDelete, size: 10)
                        .opacity(style.showsHoverFade ? (isHovering ? 1 : 0.6) : 1)
                }
            }
            .padding(.horizontal, style.paddingHorizontal)
            .padding(.vertical, style.paddingVertical)
        }
        .onHover { hovering in
            guard style.showsHoverFade else { return }
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .sheet(isPresented: $showingDetail) {
            detailView ?? AnyView(EmptyView())
        }
    }

    private var hasDetailView: Bool {
        detailView != nil
    }

    init(
        title: String,
        icon: AnyView,
        detailView: AnyView?,
        style: Style = Style(),
        onDelete: (() -> Void)? = nil
    ) {
        self.label = AnyView(AttachmentChipLabel(title: title) { icon })
        self.detailView = detailView
        self.style = style
        self.onDelete = onDelete
    }

    init(
        label: AnyView,
        detailView: AnyView?,
        style: Style = Style(),
        onDelete: (() -> Void)? = nil
    ) {
        self.label = label
        self.detailView = detailView
        self.style = style
        self.onDelete = onDelete
    }
}
