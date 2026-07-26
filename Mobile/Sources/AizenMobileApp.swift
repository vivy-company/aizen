import AizenClient
import AizenCore
import AizenSecurity
import AizenTransport
import AizenWire
import SwiftUI

@main
struct AizenMobileApp: App {
    var body: some Scene {
        WindowGroup {
            MobileRootView()
        }
    }
}

private struct MobileRootView: View {
    @StateObject private var pairing = MobilePairingStore()
    @State private var invitation = ""

    var body: some View {
        NavigationSplitView {
            List {
                Section("Hosts") {
                    switch pairing.state {
                    case .awaitingApproval(let hostName):
                        Label("Approval pending on \(hostName)", systemImage: "clock.badge.exclamationmark")
                    default:
                        Label("No paired Host", systemImage: "desktopcomputer.trianglebadge.exclamationmark")
                    }
                }
            }
            .navigationTitle("Aizen")
        } content: {
            Form {
                Section("Pair a Host") {
                    TextField("Pairing invitation", text: $invitation, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Submit pairing invitation") {
                        Task { await pairing.submit(invitationText: invitation) }
                    }
                    .disabled(invitation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pairing.state == .pairing)
                }
                Section {
                    pairingStatus
                }
            }
            .navigationTitle("Pair a Host")
        } detail: {
            ContentUnavailableView(
                "Choose a Session",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("Paired Hosts expose only the Spaces and Sessions you are authorized to access.")
            )
        }
    }

    @ViewBuilder
    private var pairingStatus: some View {
        switch pairing.state {
        case .unpaired:
            Text("Paste the pairing invitation shown by Aizen on your Mac.")
        case .pairing:
            ProgressView("Submitting secure pairing request…")
        case .awaitingApproval(let hostName):
            Text("Approve this device in Aizen on \(hostName), then reconnect.")
        case .failed(let message):
            Text(message).foregroundStyle(.red)
        }
    }
}
