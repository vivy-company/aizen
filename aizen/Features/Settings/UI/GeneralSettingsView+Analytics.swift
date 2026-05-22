import SwiftUI

extension GeneralSettingsView {
    @ViewBuilder
    var analyticsSection: some View {
        Section {
            Toggle("Share anonymous usage analytics", isOn: $analyticsEnabled)
                .help("Send anonymous app usage counts to help improve Aizen")

            Text("Helps improve Aizen by sending anonymous app usage counts. Project names, paths, prompts, terminal commands, and file contents are never sent.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Analytics")
        }
    }
}
