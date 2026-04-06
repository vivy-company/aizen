import SwiftUI

extension ActiveWorktreesView {
    var surfaceColor: Color {
        AppSurfaceTheme.backgroundColor(colorScheme: colorScheme)
    }

    var surfaceNSColor: NSColor {
        AppSurfaceTheme.backgroundNSColor(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            content
            Divider()
            footer
        }
        .frame(minWidth: 940, minHeight: 560)
        .scrollContentBackground(.hidden)
        .background(surfaceColor)
        .background(WindowBackgroundSync(color: surfaceNSColor))
        .toolbarBackground(surfaceColor, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                scopePicker
            }

            ToolbarItem(placement: .principal) {
                monitorModePicker
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    metrics.refreshNow()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .labelStyle(.titleAndIcon)

                Button(role: .destructive) {
                    showTerminateAllConfirm = true
                } label: {
                    Label("Terminate All", systemImage: "xmark.circle.fill")
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(activeWorktrees.isEmpty)
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search environments")
        .navigationTitle("Activity Monitor")
        .navigationSubtitle("\(scopeLabel) • \(sortedRows.count) environments")
        .onAppear {
            metrics.start()
            syncScopeIfNeeded()
            updateSortOrder(for: selectedMode)
        }
        .onDisappear {
            metrics.stop()
        }
        .task(id: activeWorktreeIDs) {
            syncScopeIfNeeded()
        }
        .alert("Terminate all sessions?", isPresented: $showTerminateAllConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Terminate All", role: .destructive) {
                terminateAll()
            }
        } message: {
            Text("This closes chat, terminal, browser, and file sessions in all active environments.")
        }
    }

    var content: some View {
        Group {
            if sortedRows.isEmpty {
                emptyState
            } else {
                switch selectedMode {
                case .chats:
                    chatsTable
                case .terminals:
                    terminalsTable
                case .files:
                    filesTable
                case .browsers:
                    browsersTable
                }
            }
        }
    }

}
