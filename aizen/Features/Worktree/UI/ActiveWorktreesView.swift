//
//  ActiveWorktreesView.swift
//  aizen
//
//  Activity Monitor for active environments.
//

import CoreData
import SwiftUI
import os.log

@MainActor
struct ActiveWorktreesView: View {
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @StateObject var metrics = ActiveWorktreesMetrics()

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Worktree.lastAccessed, ascending: false)],
        animation: .default
    )
    var worktrees: FetchedResults<Worktree>

    @AppStorage("terminalSessionPersistence") var sessionPersistence = false

    @State var searchText = ""
    @State var selectedMode: ActiveWorktreesMonitorMode = .chats
    @State var selectedScope: ActiveWorktreesScopeSelection = .all
    @State var selectedRowID: ActiveWorktreesMonitorRow.ID?
    @State private var showTerminateAllConfirm = false
    @State var sortOrder: [KeyPathComparator<ActiveWorktreesMonitorRow>] = [
        KeyPathComparator(\.chatSessions, order: .reverse),
        KeyPathComparator(\.lastAccessed, order: .reverse)
    ]

    private var surfaceColor: Color {
        AppSurfaceTheme.backgroundColor(colorScheme: colorScheme)
    }

    private var surfaceNSColor: NSColor {
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

    private var content: some View {
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

    private var scopePicker: some View {
        Picker("Scope", selection: $selectedScope) {
            Text("All Environments").tag(ActiveWorktreesScopeSelection.all)
            ForEach(workspaceGroups) { group in
                if group.isOther {
                    Text("Other").tag(ActiveWorktreesScopeSelection.other)
                } else if let workspaceId = group.workspaceId {
                    Text(group.name).tag(ActiveWorktreesScopeSelection.workspace(workspaceId))
                }
            }
        }
        .pickerStyle(.menu)
    }

    private var selectedModeBinding: Binding<ActiveWorktreesMonitorMode> {
        Binding(
            get: { selectedMode },
            set: { mode in
                selectedMode = mode
                selectedRowID = nil
                updateSortOrder(for: mode)
            }
        )
    }

    private var monitorModePicker: some View {
        Picker("Mode", selection: selectedModeBinding) {
            ForEach(ActiveWorktreesMonitorMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize(horizontal: true, vertical: false)
    }

    private func updateSortOrder(for mode: ActiveWorktreesMonitorMode) {
        switch mode {
        case .chats:
            sortOrder = [
                KeyPathComparator(\.chatSessions, order: .reverse),
                KeyPathComparator(\.lastAccessed, order: .reverse)
            ]
        case .terminals:
            sortOrder = [
                KeyPathComparator(\.terminalSessions, order: .reverse),
                KeyPathComparator(\.runningPanes, order: .reverse),
                KeyPathComparator(\.cpuPercent, order: .reverse)
            ]
        case .files:
            sortOrder = [
                KeyPathComparator(\.fileSessions, order: .reverse),
                KeyPathComparator(\.lastAccessed, order: .reverse)
            ]
        case .browsers:
            sortOrder = [
                KeyPathComparator(\.browserSessions, order: .reverse),
                KeyPathComparator(\.energyImpact, order: .reverse)
            ]
        }
    }

    func rowMatchesSelectedMode(_ row: ActiveWorktreesMonitorRow) -> Bool {
        switch selectedMode {
        case .chats:
            return row.chatSessions > 0
        case .terminals:
            return row.terminalSessions > 0
        case .files:
            return row.fileSessions > 0
        case .browsers:
            return row.browserSessions > 0
        }
    }

    private func syncScopeIfNeeded() {
        switch selectedScope {
        case .all:
            return
        case .other:
            if !workspaceGroups.contains(where: { $0.isOther }) {
                selectedScope = .all
            }
        case .workspace(let id):
            if !workspaceGroups.contains(where: { $0.workspaceId == id }) {
                selectedScope = .all
            }
        }
    }

}
