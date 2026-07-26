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
    var body: some View {
        NavigationSplitView {
            List {
                Section("Hosts") {
                    Label("No paired Host", systemImage: "desktopcomputer.trianglebadge.exclamationmark")
                }
            }
            .navigationTitle("Aizen")
        } content: {
            ContentUnavailableView(
                "Pair a Host",
                systemImage: "qrcode.viewfinder",
                description: Text("Scan the pairing QR code displayed by Aizen on your Mac.")
            )
        } detail: {
            ContentUnavailableView(
                "Choose a Session",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("Paired Hosts expose only the Spaces and Sessions you are authorized to access.")
            )
        }
    }
}
