//
//  aizenApp+Startup.swift
//  aizen
//
//  Created by OpenAI Codex on 05.04.26.
//

import ACP
import Sparkle

extension aizenApp {
    static func makeUpdaterController() -> SPUStandardUpdaterController {
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller.updater.automaticallyChecksForUpdates = true
        controller.updater.updateCheckInterval = 3600
        return controller
    }

    func configureStartup() {
        // Initialize crash reporter early to catch startup crashes.
        CrashReporter.shared.start()

        // Make terminal shells use the system locale instead of macOS AppleLanguages.
        setenv("GHOSTTY_MAC_LAUNCH_SOURCE", "app", 1)

        // Preload shell environment to reduce first agent-session startup latency.
        ShellEnvironment.preloadEnvironment()

        Task {
            await ProcessRegistry.shared.cleanupOrphanedProcesses()
        }
    }
}
