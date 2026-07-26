import AizenWire
import SwiftUI

struct HostServiceSettingsView: View {
    @State private var status = ReignitionHostService.status
    @State private var error: String?
    @State private var pendingPairings: [PendingPairingRequestRecordPayload] = []
    private let host = ReignitionHostComposition()

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

            if !pendingPairings.isEmpty {
                Section("Pairing Requests") {
                    ForEach(pendingPairings) { request in
                        VStack(alignment: .leading) {
                            Text(request.deviceDisplayName).font(.headline)
                            Text("\(request.devicePlatform) · \(request.fingerprint.prefix(12))").font(.footnote).foregroundStyle(.secondary)
                            HStack { Button("Reject", role: .destructive) { decide(request, approve: false) }; Button("Approve") { decide(request, approve: true) } }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .settingsSurface()
        .alert("Host Service", isPresented: errorAlert) {
            Button("OK", role: .cancel) { error = nil }
        } message: {
            Text(error ?? "")
        }
        .task { await refreshPairings() }
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

    private func refreshPairings() async { do { try await host.activate(); pendingPairings = try await host.pendingPairingRequests() } catch { self.error = error.localizedDescription } }
    private func decide(_ request: PendingPairingRequestRecordPayload, approve: Bool) { Task { do { if approve { try await host.approvePairingRequest(tokenID: request.tokenID) } else { try await host.rejectPairingRequest(tokenID: request.tokenID) }; await refreshPairings() } catch { self.error = error.localizedDescription } } }
}
