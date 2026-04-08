//
//  Ghostty.App+Callbacks.swift
//  aizen
//

import Foundation

extension Ghostty.App {
    static func wakeup(_ userdata: UnsafeMutableRawPointer?) {
        guard let userdata = userdata else { return }
        let state = Unmanaged<Ghostty.App>.fromOpaque(userdata).takeUnretainedValue()

        DispatchQueue.main.async {
            state.appTick()
        }
    }

    static func closeSurface(_ userdata: UnsafeMutableRawPointer?, processAlive: Bool) {
        guard let userdata = userdata else { return }
        let terminalView = Unmanaged<AizenTerminalSurfaceView>.fromOpaque(userdata).takeUnretainedValue()

        DispatchQueue.main.async {
            terminalView.onProcessExit?()
        }
    }
}
