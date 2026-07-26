import AizenClient
import AizenCore
import AizenSecurity
import AizenTransport
import AizenWire
import SwiftUI
import VisionKit

@main
struct AizenMobileApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var pairing = MobilePairingStore()

    var body: some Scene {
        WindowGroup {
            MobileRootView(pairing: pairing)
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .background: pairing.enterBackground()
                    case .active: Task { await pairing.enterForeground() }
                    default: break
                    }
                }
        }
    }
}

private struct MobileRootView: View {
    @ObservedObject var pairing: MobilePairingStore
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
                        Label("\(hostName) · \(spaceCount) Spaces\(pairing.isLive ? "" : " (offline)")", systemImage: "desktopcomputer.and.iphone")
                    default:
                        Label("No paired Host", systemImage: "desktopcomputer.trianglebadge.exclamationmark")
                    }
                }
                if !pairing.spaces.isEmpty {
                    Section("Spaces") {
                        ForEach(pairing.spaces) { space in
                            Button(space.name) { Task { await pairing.selectSpace(space.id) } }
                                .fontWeight(pairing.selectedSpaceID == space.id ? .semibold : .regular)
                                .disabled(!pairing.isLive)
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
                            .disabled(!pairing.isLive || newConversationTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                    if !pairing.streamingText.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Assistant · streaming").font(.caption).foregroundStyle(.secondary)
                            Text(pairing.streamingText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                    }
                    if let session = pairing.sessions.first(where: { $0.id == sessionID }) {
                        MobileSessionSummary(session: session, pairing: pairing)
                    }
                    HStack(alignment: .bottom) {
                        TextField("Message", text: $composer, axis: .vertical)
                        Button("Send") {
                            let content = composer
                            composer = ""
                            Task { await pairing.sendMessage(content) }
                        }
                        .disabled(!pairing.isLive || composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding()
                    if pairing.activeRunID != nil {
                        Button("Cancel active Run", role: .destructive) { Task { await pairing.cancelActiveRun() } }
                            .padding(.bottom)
                            .disabled(!pairing.isLive)
                    }
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

private struct MobileSessionSummary: View {
    let session: Session
    @ObservedObject var pairing: MobilePairingStore

    private var attachedResources: [Resource] {
        pairing.resources.filter { session.resourceIDs.contains($0.id) }
    }

    var body: some View {
        List {
            Section("Context") {
                LabeledContent("Session", value: session.kind.rawValue)
                LabeledContent("Execution", value: executionLabel)
                if attachedResources.isEmpty {
                    Text("No attached resources").foregroundStyle(.secondary)
                } else {
                    ForEach(attachedResources) { resource in
                        LabeledContent(resource.title, value: resource.kind.rawValue)
                    }
                }
            }
            Section("Runs") {
                let sessionRuns = pairing.runs.filter { $0.sessionID == session.id }
                if sessionRuns.isEmpty {
                    Text("No active or recent Runs").foregroundStyle(.secondary)
                } else {
                    ForEach(sessionRuns) { run in
                        LabeledContent(run.id.description.prefix(8), value: run.lifecycle.rawValue)
                    }
                }
            }
            Section("Operations") {
                let sessionOperations = pairing.operations.filter { $0.sessionID == session.id }
                if sessionOperations.isEmpty {
                    Text("No active or recent operations").foregroundStyle(.secondary)
                } else {
                    ForEach(sessionOperations) { operation in
                        VStack(alignment: .leading) {
                            Text(operation.lifecycle.rawValue.capitalized)
                            if let progress = operation.progress {
                                ProgressView(value: progress)
                            }
                            if let failure = operation.failureDescription {
                                Text(failure).font(.caption).foregroundStyle(.red)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxHeight: 260)
    }

    private var executionLabel: String {
        guard let id = session.executionContextID,
              let context = pairing.executionContexts.first(where: { $0.id == id }) else {
            return "Projectless"
        }
        return context.kind.rawValue
    }
}
