import AizenClient
import AizenCore
import AizenSecurity
import AizenTransport
import AizenWire
import SwiftUI
import VisionKit

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
    @State private var showsScanner = false
    @State private var newConversationTitle = ""
    @State private var composer = ""

    var body: some View {
        NavigationSplitView {
            List {
                Section("Hosts") {
                    switch pairing.state {
                    case .awaitingApproval(let hostName):
                        Label("Approval pending on \(hostName)", systemImage: "clock.badge.exclamationmark")
                    case .ready(let hostName, let spaceCount):
                        Label("\(hostName) · \(spaceCount) Spaces", systemImage: "desktopcomputer.and.iphone")
                    default:
                        Label("No paired Host", systemImage: "desktopcomputer.trianglebadge.exclamationmark")
                    }
                }
                if !pairing.spaces.isEmpty {
                    Section("Spaces") {
                        ForEach(pairing.spaces) { space in
                            Button(space.name) { Task { await pairing.selectSpace(space.id) } }
                                .fontWeight(pairing.selectedSpaceID == space.id ? .semibold : .regular)
                        }
                    }
                }
            }
            .navigationTitle("Aizen")
        } content: {
            Group {
                if pairing.spaces.isEmpty {
            Form {
                Section("Pair a Host") {
                    Button("Scan pairing QR code") { showsScanner = true }
                        .disabled(!DataScannerViewController.isSupported || !DataScannerViewController.isAvailable)
                    TextField("Pairing invitation", text: $invitation, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Submit pairing invitation") {
                        Task { await pairing.submit(invitationText: invitation) }
                    }
                    .disabled(invitation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pairing.state == .pairing)
                    Button("Reconnect approved Host") { Task { await pairing.reconnect() } }
                        .disabled(pairing.state == .pairing)
                }
                Section {
                    pairingStatus
                }
            }
            .navigationTitle("Pair a Host")
            .sheet(isPresented: $showsScanner) {
                PairingQRScanner(
                    didScan: { value in
                        invitation = value
                        showsScanner = false
                        Task { await pairing.submit(invitationText: value) }
                    },
                    didFail: { message in
                        showsScanner = false
                        pairing.recordScannerFailure(message)
                    }
                )
                .ignoresSafeArea()
            }
                } else {
                    VStack(spacing: 0) {
                        List(pairing.sessions) { session in
                            Button { Task { await pairing.selectSession(session.id) } } label: {
                                VStack(alignment: .leading) {
                                    Text(session.title)
                                    Text(session.kind.rawValue).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        HStack {
                            TextField("New conversation", text: $newConversationTitle)
                            Button("Create") {
                                let title = newConversationTitle
                                newConversationTitle = ""
                                Task { await pairing.createConversation(title: title) }
                            }
                            .disabled(newConversationTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .padding()
                    }
                    .navigationTitle(pairing.spaces.first(where: { $0.id == pairing.selectedSpaceID })?.name ?? "Sessions")
                }
            }
        } detail: {
            if let sessionID = pairing.selectedSessionID {
                VStack(spacing: 0) {
                    List(pairing.messages) { message in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(message.role.rawValue.capitalized).font(.caption).foregroundStyle(.secondary)
                            Text(message.content)
                        }
                    }
                    HStack(alignment: .bottom) {
                        TextField("Message", text: $composer, axis: .vertical)
                        Button("Send") {
                            let content = composer
                            composer = ""
                            Task { await pairing.sendMessage(content) }
                        }
                        .disabled(composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding()
                }
                .navigationTitle(pairing.sessions.first(where: { $0.id == sessionID })?.title ?? "Conversation")
            } else {
                ContentUnavailableView("Choose a Session", systemImage: "bubble.left.and.bubble.right", description: Text("Paired Hosts expose only the Spaces and Sessions you are authorized to access."))
            }
        }
    }

    @ViewBuilder
    private var pairingStatus: some View {
        switch pairing.state {
        case .unpaired:
            Text("Scan or paste the pairing invitation shown by Aizen on your Mac.")
        case .pairing:
            ProgressView("Submitting secure pairing request…")
        case .awaitingApproval(let hostName):
            Text("Approve this device in Aizen on \(hostName), then reconnect.")
        case .ready(let hostName, let spaceCount):
            Text("Connected to \(hostName). \(spaceCount) authorized Spaces are available.")
        case .failed(let message):
            Text(message).foregroundStyle(.red)
        }
    }
}
