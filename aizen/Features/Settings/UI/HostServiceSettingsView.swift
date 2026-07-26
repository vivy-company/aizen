import AizenWire
import SwiftUI

struct HostServiceSettingsView: View {
    @State private var status = ReignitionHostService.status
    @State private var isReachable = false
    @State private var productVersion: String?
    @State private var protocolRange: String?
    @State private var error: String?
    @State private var isRepairing = false
    @State private var pendingPairings: [PendingPairingRequestRecordPayload] = []
    private let host = ReignitionHostComposition()

    var body: some View {
        Form {
            Section("Local Host") {
                LabeledContent("Service status", value: status.title)
                Text(status.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                LabeledContent("Host", value: isReachable ? "Reachable" : "Unavailable")
                if let productVersion {
                    LabeledContent("Host version", value: productVersion)
                }
                if let protocolRange {
                    LabeledContent("Protocol generation", value: protocolRange)
                }
            }

            Section {
                Button(status == .enabled ? "Restart Host Service" : "Repair Host Service") {
                    Task { await repair() }
                }
                .disabled(isRepairing)

                Button("Refresh Status") {
                    Task { await refresh() }
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
        .task { await refresh() }
    }

    private var errorAlert: Binding<Bool> {
        Binding(get: { error != nil }, set: { if !$0 { error = nil } })
    }

    private func repair() async {
        isRepairing = true
        defer { isRepairing = false }
        do {
            try ReignitionHostService.repair()
            status = ReignitionHostService.status
            await refresh()
        } catch {
            status = ReignitionHostService.status
            self.error = error.localizedDescription
        }
    }

    private func refresh() async {
        status = ReignitionHostService.status
        do {
            let capabilities = try await host.activate()
            isReachable = true
            productVersion = capabilities.productVersion
            protocolRange = "\(capabilities.minimumProtocolGeneration)…\(capabilities.maximumProtocolGeneration)"
            pendingPairings = try await host.pendingPairingRequests()
        } catch {
            isReachable = false
            productVersion = nil
            protocolRange = nil
            pendingPairings = []
            self.error = error.localizedDescription
        }
    }

    private func decide(_ request: PendingPairingRequestRecordPayload, approve: Bool) {
        Task {
            do {
                if approve {
                    try await host.approvePairingRequest(tokenID: request.tokenID)
                } else {
                    try await host.rejectPairingRequest(tokenID: request.tokenID)
                }
                await refresh()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
