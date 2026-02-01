//
//  OpenCodeConfigService+Finder.swift
//  aizen
//
//  Finder integration for OpenCode config
//

import AppKit
import Foundation

extension OpenCodeConfigService {
    func openConfigInFinder() async {
        let path = currentConfigPath()
        let directory = currentConfigDirectory()
        await MainActor.run {
            if FileManager.default.fileExists(atPath: path) {
                let url = URL(fileURLWithPath: path)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } else {
                let url = URL(fileURLWithPath: directory)
                NSWorkspace.shared.open(url)
            }
        }
    }
}
