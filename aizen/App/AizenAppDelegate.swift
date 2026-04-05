//
//  AizenAppDelegate.swift
//  aizen
//
//  Created by OpenAI Codex on 05.04.26.
//

import AppKit

// App delegate to handle window restoration cleanup
class AizenAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Disable App Nap to prevent activation delays when clicking dock icon
        ProcessInfo.processInfo.disableAutomaticTermination("Aizen needs responsive activation")
        ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
            reason: "Prevent App Nap for responsive dock activation"
        )

        // Close duplicate main windows that macOS incorrectly restored
        // Keep only one main window (non-GitPanel window)
        DispatchQueue.main.async {
            let windows = NSApp.windows.filter { window in
                // Keep windows that are Git panels (we restore those ourselves)
                // or the first main window
                window.identifier != NSUserInterfaceItemIdentifier("GitPanelWindow") &&
                window.isVisible &&
                !window.isMiniaturized
            }

            // If there are multiple main windows, close the extras
            if windows.count > 1 {
                // Keep the first one, close the rest
                for window in windows.dropFirst() {
                    window.close()
                }
            }
        }

        // Best-effort CLI symlink install (non-blocking)
        DispatchQueue.global(qos: .utility).async {
            if CLISymlinkService.installedSymlinkURL() == nil {
                _ = CLISymlinkService.install()
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        DispatchQueue.main.async {
            for url in urls {
                DeepLinkHandler.shared.handle(url)
            }
        }
    }
}
