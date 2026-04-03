//
//  WorktreeSessionTabs+SupportViews.swift
//  aizen
//
//  Supporting views for the worktree session tab strip
//

import SwiftUI

struct TerminalPersistenceIndicator: View {
    @AppStorage("terminalSessionPersistence") private var sessionPersistence = false

    var body: some View {
        if sessionPersistence {
            Image(systemName: "pin.fill")
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
                .help("Session persists across app restarts")
        }
    }
}

struct PendingPermissionIndicator: View {
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .fill(Color.orange)
            .frame(width: 8, height: 8)
            .opacity(isAnimating ? 0.4 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isAnimating)
            .onAppear { isAnimating = true }
            .help("Pending permission request - click to respond")
    }
}

struct SessionTabButton<Content: View>: View {
    let isSelected: Bool
    let action: () -> Void
    let content: Content

    @State private var isHovering = false

    init(isSelected: Bool, action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.isSelected = isSelected
        self.action = action
        self.content = content()
    }

    var body: some View {
        Button(action: action) {
            content
                .padding(.leading, 6)
                .padding(.trailing, 12)
                .padding(.vertical, 6)
                .background(
                    isSelected ?
                    Color(nsColor: .separatorColor) :
                    (isHovering ? Color(nsColor: .separatorColor).opacity(0.5) : Color.clear),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

struct NavigationArrowButton: View {
    let icon: String
    let action: () -> Void
    let help: String

    @State private var isHovering = false
    @State private var clickTrigger = 0

    var body: some View {
        let button = Button(action: {
            clickTrigger += 1
            action()
        }) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .frame(width: 24, height: 24)
                .background(
                    isHovering ? Color(nsColor: .separatorColor).opacity(0.5) : Color.clear,
                    in: Circle()
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .help(help)

        if #available(macOS 14.0, *) {
            button.symbolEffect(.bounce, value: clickTrigger)
        } else {
            button
        }
    }
}

struct WheelScrollHandler: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> WheelScrollView {
        let view = WheelScrollView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: WheelScrollView, context: Context) {
        nsView.onScroll = onScroll
    }

    class WheelScrollView: NSView {
        var onScroll: ((CGFloat) -> Void)?

        override func scrollWheel(with event: NSEvent) {
            if abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
                onScroll?(event.scrollingDeltaY)
            }
            super.scrollWheel(with: event)
        }
    }
}
