import AppKit
import SwiftUI
import os.log

extension GeneralSettingsView {
    @ViewBuilder
    var resetSection: some View {
        Section {
            Text("settings.advanced.reset.description")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button(role: .destructive) {
                showingResetConfirmation = true
            } label: {
                Label("settings.advanced.reset.button", systemImage: "trash")
            }
        } header: {
            Text("settings.advanced.reset.title")
                .foregroundStyle(.red)
        }
    }

    func resetApp() {
        let bundleURL = Bundle.main.bundleURL
        let currentPID = ProcessInfo.processInfo.processIdentifier

        guard let bundleID = Bundle.main.bundleIdentifier else {
            logger.error("Cannot get bundle identifier")
            return
        }

        let coordinator = PersistenceController.shared.container.persistentStoreCoordinator
        let storeURL = coordinator.persistentStores.first?.url?.deletingLastPathComponent().path ?? ""
        let storeName = coordinator.persistentStores.first?.url?.deletingPathExtension().lastPathComponent ?? "aizen"

        let script = """
        #!/bin/bash

        kill -9 \(currentPID) 2>/dev/null || true
        sleep 0.5

        defaults delete "\(bundleID)" 2>/dev/null || true

        if [ -n "\(storeURL)" ]; then
            rm -f "\(storeURL)/\(storeName).sqlite"* 2>/dev/null || true
        fi

        rm -rf ~/Library/Application\\ Support/"\(bundleID)"/*.sqlite* 2>/dev/null || true
        rm -rf ~/Library/Containers/"\(bundleID)"/Data/Library/Application\\ Support/*.sqlite* 2>/dev/null || true

        open -n "\(bundleURL.path)"

        rm -f "$0"
        """

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("aizen-reset-\(UUID().uuidString).sh")

        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/bash")
            task.arguments = [scriptURL.path]
            try task.run()

            for window in NSApplication.shared.windows {
                window.close()
            }
        } catch {
            logger.error("Failed to create reset script: \(error.localizedDescription)")
        }
    }
}
