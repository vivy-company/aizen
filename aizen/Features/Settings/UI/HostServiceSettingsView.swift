import SwiftUI

struct HostServiceSettingsView: View {
    @State private var status = ReignitionHostService.status
    @State private var error: String?

    var body: some View {
        Form {
            Section("Local Host") {
                LabeledContent("Service status", value: status.title)
                Text(status.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Repair Host Service") {
                    repair()
                }
                .disabled(status == .enabled)

                Button("Refresh Status") {
                    status = ReignitionHostService.status
                }
            } footer: {
                Text("The Host owns Aizen 2.0 storage, agent runs, and terminal lifetime. It continues running after Aizen windows close.")
            }
        }
        .formStyle(.grouped)
        .settingsSurface()
        .alert("Host Service", isPresented: errorAlert) {
            Button("OK", role: .cancel) { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private var errorAlert: Binding<Bool> {
        Binding(get: { error != nil }, set: { if !$0 { error = nil } })
    }

    private func repair() {
        do {
            try ReignitionHostService.registerIfNeeded()
            status = ReignitionHostService.status
        } catch {
            status = ReignitionHostService.status
            self.error = error.localizedDescription
        }
    }
}
