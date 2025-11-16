//
//  WorktreeToolbar.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 04.11.25.
//

import SwiftUI

// MARK: - Open In App Button

struct OpenInAppButton: View {
    let lastOpenedApp: DetectedApp?
    @ObservedObject var appDetector: AppDetector
    let onOpenInLastApp: () -> Void
    let onOpenInDetectedApp: (DetectedApp) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button {
                onOpenInLastApp()
            } label: {
                if let app = lastOpenedApp {
                    AppMenuLabel(app: app)
                } else if let finder = appDetector.getApps(for: .finder).first {
                    AppMenuLabel(app: finder)
                } else {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 11))
                }
            }
            .buttonStyle(.borderless)
            .padding(8)
            .help(lastOpenedApp?.name ?? "Open in Finder")

            Divider()
                .frame(height: 16)

            Menu {
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
                        }.buttonStyle(.borderless)

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
}

// MARK: - Git Status View

struct GitStatusView: View {
    let additions: Int
    let deletions: Int
    let untrackedFiles: Int

    var body: some View {
        HStack(spacing: 8) {
            if additions > 0 {
                Text("+\(additions)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }

            if deletions > 0 {
                Text("-\(deletions)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.red)
                    .transition(.opacity)
            }

            if untrackedFiles > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 10))
                    Text("\(untrackedFiles)")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.orange)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .animation(.easeInOut(duration: 0.2), value: additions)
        .animation(.easeInOut(duration: 0.2), value: deletions)
        .animation(.easeInOut(duration: 0.2), value: untrackedFiles)
    }
}
