//
//  AdvancedSettingsView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 27.10.25.
//

import SwiftUI
import os.log

struct AdvancedSettingsView: View {
    private let logger = Logger.settings
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showingResetConfirmation = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("settings.advanced.reset.title")
                        .font(.headline)

                    Text("settings.advanced.reset.description")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button(role: .destructive) {
                        showingResetConfirmation = true
                    } label: {
                        Label("settings.advanced.reset.button", systemImage: "trash")
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .formStyle(.grouped)
        .alert(LocalizedStringKey("settings.advanced.reset.alert.title"), isPresented: $showingResetConfirmation) {
            Button(LocalizedStringKey("settings.advanced.reset.alert.cancel"), role: .cancel) {}
            Button(LocalizedStringKey("settings.advanced.reset.alert.confirm"), role: .destructive) {
                resetApp()
            }
        } message: {
            Text("settings.advanced.reset.alert.message")
        }
    }

    private func resetApp() {
        // Get paths before we destroy everything
        let bundleURL = Bundle.main.bundleURL
        let currentPID = ProcessInfo.processInfo.processIdentifier

        guard let bundleID = Bundle.main.bundleIdentifier else {
            logger.error("Cannot get bundle identifier")
            return
        }

        // Get actual store location from persistent container
        let coordinator = PersistenceController.shared.container.persistentStoreCoordinator
        let storeURL = coordinator.persistentStores.first?.url?.deletingLastPathComponent().path ?? ""
        let storeName = coordinator.persistentStores.first?.url?.deletingPathExtension().lastPathComponent ?? "aizen"

        // Create a shell script to handle the reset asynchronously
        let script = """
        #!/bin/bash

        # Kill the old app process immediately
        kill -9 \(currentPID) 2>/dev/null || true

        # Wait a moment for app to fully exit
        sleep 0.5

        # Clear UserDefaults
        defaults delete "\(bundleID)" 2>/dev/null || true

        # Delete Core Data store files from actual location
        if [ -n "\(storeURL)" ]; then
            rm -f "\(storeURL)/\(storeName).sqlite"* 2>/dev/null || true
        fi

        # Also try common locations as fallback
        rm -rf ~/Library/Application\\ Support/"\(bundleID)"/*.sqlite* 2>/dev/null || true
        rm -rf ~/Library/Containers/"\(bundleID)"/Data/Library/Application\\ Support/*.sqlite* 2>/dev/null || true

        # Launch new instance using -n flag for new instance
        open -n "\(bundleURL.path)"

        # Clean up this script
        rm -f "$0"
        """

        // Write script to temp file
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("aizen-reset-\(UUID().uuidString).sh")

        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

            // Execute script in background
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/bash")
            task.arguments = [scriptURL.path]
            try task.run()

            // Close all windows first to prevent Core Data access
            for window in NSApplication.shared.windows {
                window.close()
            }

            // Script will kill this process, so just return
            // No need for timer - script handles everything
        } catch {
            logger.error("Failed to create reset script: \(error.localizedDescription)")
        }
    }
}

#Preview {
    AdvancedSettingsView()
}
