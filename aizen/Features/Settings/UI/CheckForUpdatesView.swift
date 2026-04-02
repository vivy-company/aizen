//
//  CheckForUpdatesView.swift
//  aizen
//
//  Created for Sparkle auto-update integration
//

import SwiftUI
import Sparkle
import Combine

struct CheckForUpdatesView: View {
    @ObservedObject private var checkForUpdatesStore: CheckForUpdatesStore

    init(updater: SPUUpdater) {
        checkForUpdatesStore = CheckForUpdatesStore(updater: updater)
    }

    var body: some View {
        Button("Check for Updates...") {
            checkForUpdatesStore.checkForUpdates()
        }
        .disabled(!checkForUpdatesStore.canCheckForUpdates)
    }
}

final class CheckForUpdatesStore: ObservableObject {
    @Published var canCheckForUpdates = false

    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater

        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }
}
