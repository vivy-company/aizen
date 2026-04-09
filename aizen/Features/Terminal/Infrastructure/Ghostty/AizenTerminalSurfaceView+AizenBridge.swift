import AppKit
import Foundation
import GhosttyKit

@MainActor
final class AizenTerminalSurfaceView: Ghostty.SurfaceView {
    let paneId: String
    weak var ghosttyAppWrapper: Ghostty.App?
    var surfaceReference: Ghostty.SurfaceReference?
    var onProcessExit: (() -> Void)?
    var onFocus: (() -> Void)?
    var onTitleChange: ((String) -> Void)?
    var onReady: (() -> Void)?
    var onProgressReport: ((GhosttyProgressState, Int?) -> Void)?
    var didSignalReady = false

    init(
        frame: NSRect,
        worktreePath: String,
        ghosttyApp: ghostty_app_t,
        appWrapper: Ghostty.App? = nil,
        paneId: String? = nil,
        command: String? = nil
    ) {
        var config = Ghostty.SurfaceConfiguration()
        config.workingDirectory = worktreePath
        config.initialInput = if let command, !command.isEmpty { command + "\n" } else { nil }
        self.paneId = paneId ?? UUID().uuidString
        self.ghosttyAppWrapper = appWrapper
        super.init(ghosttyApp, baseConfig: config)

        let initialFrame = if frame.width > 0 && frame.height > 0 {
            frame
        } else {
            NSRect(x: 0, y: 0, width: 800, height: 600)
        }
        self.frame = initialFrame

        if let surface, let appWrapper {
            self.surfaceReference = appWrapper.registerSurface(surface)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        let appWrapper = ghosttyAppWrapper
        let surfaceReference = surfaceReference
        if let appWrapper, let surfaceReference {
            Task { @MainActor in
                appWrapper.unregisterSurface(surfaceReference)
            }
        }
    }

    override func focusDidChange(_ focused: Bool) {
        super.focusDidChange(focused)
        if focused {
            onFocus?()
        }
    }

    /// Keep Ghostty's per-surface focus state in sync with Aizen's pane selection
    /// even when AppKit responder transitions are delayed or skipped.
    func setGhosttyFocused(_ focused: Bool) {
        super.focusDidChange(focused)
    }

    func showResizeOverlay() {
    }
}
