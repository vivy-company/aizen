import AppKit
import SwiftUI

@MainActor
final class AizenTerminalSurfaceHostCoordinator {
    let adapter: AizenTerminalSurfaceAdapter
    private var exitCheckTask: Task<Void, Never>?
    private var monitoredSurfaceID: ObjectIdentifier?

    init(adapter: AizenTerminalSurfaceAdapter) {
        self.adapter = adapter
    }

    func startMonitoring(surface: AizenTerminalSurfaceView) {
        let surfaceID = ObjectIdentifier(surface)
        guard monitoredSurfaceID != surfaceID || exitCheckTask == nil else { return }

        stopMonitoring()
        monitoredSurfaceID = surfaceID
        exitCheckTask = Task { @MainActor [weak self, weak surface] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, let self, let surface else { break }
                if surface.processExited {
                    self.adapter.onProcessExit()
                    break
                }
            }
        }
    }

    func stopMonitoring() {
        exitCheckTask?.cancel()
        exitCheckTask = nil
        monitoredSurfaceID = nil
    }

    deinit {
        exitCheckTask?.cancel()
    }
}

struct AizenTerminalSurfaceHost: NSViewRepresentable {
    let surfaceView: AizenTerminalSurfaceView
    let adapter: AizenTerminalSurfaceAdapter
    let size: CGSize

    func makeCoordinator() -> AizenTerminalSurfaceHostCoordinator {
        AizenTerminalSurfaceHostCoordinator(adapter: adapter)
    }

    func makeNSView(context: Context) -> NSView {
        adapter.applyCallbacks(to: surfaceView)
        context.coordinator.startMonitoring(surface: surfaceView)
        return AizenTerminalScrollView(contentSize: size, surfaceView: surfaceView)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        adapter.applyCallbacks(to: surfaceView)
        context.coordinator.startMonitoring(surface: surfaceView)

        if let scrollView = nsView as? AizenTerminalScrollView {
            scrollView.updateContentSize(size)
        } else {
            let currentSize = nsView.frame.size
            if abs(currentSize.width - size.width) > 0.5 || abs(currentSize.height - size.height) > 0.5 {
                var frame = nsView.frame
                frame.size = size
                nsView.frame = frame
            }
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: AizenTerminalSurfaceHostCoordinator) {
        coordinator.stopMonitoring()
    }
}
