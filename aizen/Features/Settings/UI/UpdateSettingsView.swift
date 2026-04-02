//
//  UpdateSettingsView.swift
//  aizen
//
//  Settings view for Sparkle auto-update preferences
//

import SwiftUI
import Sparkle
import Combine

struct UpdateSettingsView: View {
    @ObservedObject private var updaterStore: UpdaterStore

    init(updater: SPUUpdater) {
        updaterStore = UpdaterStore(updater: updater)
    }

    var body: some View {
        Form {
            Section(header: Text("Updates")) {
                Toggle("Automatically check for updates", isOn: $updaterStore.automaticallyChecksForUpdates)
                    .help("Check for updates automatically on app launch and in the background")

                Toggle("Automatically download updates", isOn: $updaterStore.automaticallyDownloadsUpdates)
                    .help("Download updates automatically without asking")
                    .disabled(!updaterStore.automaticallyChecksForUpdates)

                HStack {
                    Text("Last checked:")
                    Spacer()
                    if let lastCheckDate = updaterStore.lastUpdateCheckDate {
                        Text(lastCheckDate, style: .relative)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Never")
                            .foregroundColor(.secondary)
                    }
                }

                Button("Check Now") {
                    updaterStore.checkForUpdates()
                }
                .disabled(!updaterStore.canCheckForUpdates)
            }
        }
        .formStyle(.grouped)
        .settingsSheetChrome()
        .frame(width: 450)
    }
}

final class UpdaterStore: ObservableObject {
    @Published var automaticallyChecksForUpdates: Bool {
        didSet {
            updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    @Published var automaticallyDownloadsUpdates: Bool {
        didSet {
            updater.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates
        }
    }

    @Published var lastUpdateCheckDate: Date?
    @Published var canCheckForUpdates = false

    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        self.automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
        self.lastUpdateCheckDate = updater.lastUpdateCheckDate

        updater.publisher(for: \.automaticallyChecksForUpdates)
            .assign(to: &$automaticallyChecksForUpdates)

        updater.publisher(for: \.automaticallyDownloadsUpdates)
            .assign(to: &$automaticallyDownloadsUpdates)

        updater.publisher(for: \.lastUpdateCheckDate)
            .assign(to: &$lastUpdateCheckDate)

        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }
}
