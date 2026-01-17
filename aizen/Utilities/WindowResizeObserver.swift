//
//  WindowResizeObserver.swift
//  aizen
//
//  Tracks live window resize state for SwiftUI views
//

import AppKit
import SwiftUI

struct WindowResizeObserver: NSViewRepresentable {
    @Binding var isResizing: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isResizing: $isResizing)
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.attach(to: nsView)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject {
        private var isResizing: Binding<Bool>
        private weak var window: NSWindow?
        private var willStartObserver: NSObjectProtocol?
        private var didEndObserver: NSObjectProtocol?

        init(isResizing: Binding<Bool>) {
            self.isResizing = isResizing
        }

        func attach(to view: NSView) {
            guard let newWindow = view.window else { return }
            guard newWindow !== window else { return }
            detach()
            window = newWindow
            observe(window: newWindow)
        }

        func detach() {
            if let willStartObserver = willStartObserver {
                NotificationCenter.default.removeObserver(willStartObserver)
            }
            if let didEndObserver = didEndObserver {
                NotificationCenter.default.removeObserver(didEndObserver)
            }
            willStartObserver = nil
            didEndObserver = nil
            window = nil
            if isResizing.wrappedValue {
                isResizing.wrappedValue = false
            }
        }

        private func observe(window: NSWindow) {
            let center = NotificationCenter.default
            willStartObserver = center.addObserver(
                forName: NSWindow.willStartLiveResizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                if !self.isResizing.wrappedValue {
                    self.isResizing.wrappedValue = true
                }
            }

            didEndObserver = center.addObserver(
                forName: NSWindow.didEndLiveResizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                if self.isResizing.wrappedValue {
                    self.isResizing.wrappedValue = false
                }
            }
        }
    }
}
