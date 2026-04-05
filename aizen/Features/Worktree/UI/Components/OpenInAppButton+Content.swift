import SwiftUI

extension OpenInAppButton {
    var body: some View {
        HStack(spacing: 0) {
            Button {
                onOpenInLastApp()
            } label: {
                primaryLabel
            }
            .buttonStyle(.borderless)
            .padding(8)
            .help(lastOpenedApp?.name ?? "Open in Finder")

            Divider()
                .frame(height: 16)

            Menu {
                menuContent
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
            }
            .buttonStyle(.borderless)
            .padding(8)
            .imageScale(.small)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    @ViewBuilder
    var primaryLabel: some View {
        if let app = lastOpenedApp {
            AppMenuLabel(app: app)
        } else if let finder = appDetector.getApps(for: .finder).first {
            AppMenuLabel(app: finder)
        } else {
            Image(systemName: "arrow.up.forward.app")
                .font(.system(size: 11))
        }
    }

    @ViewBuilder
    var menuContent: some View {
        if let finder = appDetector.getApps(for: .finder).first {
            Button {
                onOpenInDetectedApp(finder)
            } label: {
                AppMenuLabel(app: finder)
            }
            .buttonStyle(.plain)
        }

        let terminals = appDetector.getTerminals()
        if !terminals.isEmpty {
            Divider()
            ForEach(terminals) { app in
                Button {
                    onOpenInDetectedApp(app)
                } label: {
                    AppMenuLabel(app: app)
                        .imageScale(.small)
                }
                .buttonStyle(.borderless)
            }
        }

        let editors = appDetector.getEditors()
        if !editors.isEmpty {
            Divider()
            ForEach(editors) { app in
                Button {
                    onOpenInDetectedApp(app)
                } label: {
                    AppMenuLabel(app: app)
                        .imageScale(.small)
                }
            }
        }
    }
}
