import SwiftUI

extension GeneralSettingsView {
    @ViewBuilder
    var toolbarSection: some View {
        Section("Toolbar") {
            Toggle("Open in External App", isOn: $showOpenInApp)
                .help("Show the 'Open in...' button for opening environment in third-party apps")

            Toggle("Git Status", isOn: $showGitStatus)
                .help("Show the Git status indicator")

            Toggle("Xcode Build", isOn: $showXcodeBuild)
                .help("Show Xcode build button for projects with .xcodeproj or .xcworkspace")
        }
    }
}
