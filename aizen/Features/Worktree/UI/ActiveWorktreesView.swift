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
    @State private var selectedMode: ActiveWorktreesMonitorMode = .chats
    @State var selectedScope: ActiveWorktreesScopeSelection = .all
    @State private var selectedRowID: ActiveWorktreesMonitorRow.ID?
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

    private var chatsTable: some View {
        Table(sortedRows, selection: $selectedRowID, sortOrder: $sortOrder) {
            TableColumn("Environment", value: \.processName) { row in
                processCell(for: row)
            }

            TableColumn("Chats", value: \.chatSessions) { row in
                Text("\(row.chatSessions)")
                    .font(.system(.body, design: .monospaced))
            }
            .width(min: 64, ideal: 80, max: 96)

            TableColumn("% CPU", value: \.cpuPercent) { row in
                Text(row.cpuPercent, format: .number.precision(.fractionLength(1)))
                    .font(.system(.body, design: .monospaced))
            }
            .width(min: 70, ideal: 90, max: 110)

            TableColumn("Memory", value: \.memoryBytes) { row in
                Text(row.memoryBytes.formattedBytes())
                    .font(.system(.body, design: .monospaced))
            }
            .width(min: 90, ideal: 120, max: 140)

            TableColumn("Last Active", value: \.lastAccessed) { row in
                lastAccessedCell(for: row)
            }
            .width(min: 112, ideal: 140, max: 170)

            TableColumn("Action") { row in
                actionCell(for: row)
            }
            .width(min: 88, ideal: 100, max: 120)
        }
        .tableStyle(.inset)
    }

    private var terminalsTable: some View {
        Table(sortedRows, selection: $selectedRowID, sortOrder: $sortOrder) {
            TableColumn("Environment", value: \.processName) { row in
                processCell(for: row)
            }

            TableColumn("Terminals", value: \.terminalSessions) { row in
                Text("\(row.terminalSessions)")
                    .font(.system(.body, design: .monospaced))
            }
            .width(min: 74, ideal: 96, max: 116)

            TableColumn("Running Panes", value: \.runningPanes) { row in
                Text("\(row.runningPanes)")
                    .font(.system(.body, design: .monospaced))
            }
            .width(min: 96, ideal: 120, max: 138)

            TableColumn("Live Panes", value: \.livePanes) { row in
                Text("\(row.livePanes)")
                    .font(.system(.body, design: .monospaced))
            }
            .width(min: 84, ideal: 106, max: 126)

            TableColumn("State", value: \.terminalStateSortOrder) { row in
                terminalStateCell(for: row)
            }
            .width(min: 96, ideal: 110, max: 128)

            TableColumn("% CPU", value: \.cpuPercent) { row in
                Text(row.cpuPercent, format: .number.precision(.fractionLength(1)))
                    .font(.system(.body, design: .monospaced))
            }
            .width(min: 70, ideal: 90, max: 110)

            TableColumn("Action") { row in
                actionCell(for: row)
            }
            .width(min: 88, ideal: 100, max: 120)
        }
        .tableStyle(.inset)
    }

    private var filesTable: some View {
        Table(sortedRows, selection: $selectedRowID, sortOrder: $sortOrder) {
            TableColumn("Environment", value: \.processName) { row in
                processCell(for: row)
            }

            TableColumn("Files", value: \.fileSessions) { row in
                Text("\(row.fileSessions)")
                    .font(.system(.body, design: .monospaced))
            }
            .width(min: 56, ideal: 72, max: 88)

            TableColumn("Path", value: \.path) { row in
                Text(row.path)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .width(min: 200, ideal: 320, max: 460)

            TableColumn("Last Active", value: \.lastAccessed) { row in
                lastAccessedCell(for: row)
            }
            .width(min: 112, ideal: 140, max: 170)

            TableColumn("Action") { row in
                actionCell(for: row)
            }
            .width(min: 88, ideal: 100, max: 120)
        }
        .tableStyle(.inset)
    }

    private var browsersTable: some View {
        Table(sortedRows, selection: $selectedRowID, sortOrder: $sortOrder) {
            TableColumn("Environment", value: \.processName) { row in
                processCell(for: row)
            }

            TableColumn("Browsers", value: \.browserSessions) { row in
                Text("\(row.browserSessions)")
                    .font(.system(.body, design: .monospaced))
            }
            .width(min: 74, ideal: 96, max: 116)

            TableColumn("% CPU", value: \.cpuPercent) { row in
                Text(row.cpuPercent, format: .number.precision(.fractionLength(1)))
                    .font(.system(.body, design: .monospaced))
            }
            .width(min: 70, ideal: 90, max: 110)

            TableColumn("Memory", value: \.memoryBytes) { row in
                Text(row.memoryBytes.formattedBytes())
                    .font(.system(.body, design: .monospaced))
            }
            .width(min: 90, ideal: 120, max: 140)

            TableColumn("Energy", value: \.energyImpact) { row in
                energyCell(for: row)
            }
            .width(min: 80, ideal: 90, max: 110)

            TableColumn("Action") { row in
                actionCell(for: row)
            }
            .width(min: 88, ideal: 100, max: 120)
        }
        .tableStyle(.inset)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            footerCard {
                VStack(alignment: .leading, spacing: 4) {
                    footerStatRow(label: "System", value: String(format: "%.2f%%", metrics.systemCPUPercent), tint: .red)
                    footerStatRow(label: "User", value: String(format: "%.2f%%", metrics.userCPUPercent), tint: .blue)
                    footerStatRow(label: "Idle", value: String(format: "%.2f%%", metrics.idleCPUPercent), tint: .secondary)
                }
            }

            footerCard {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CPU Load")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Sparkline(
                        history: metrics.cpuHistory.map { $0 / 100.0 },
                        lineColor: selectedMode.tintColor
                    )
                    .frame(height: 26)
                }
            }

            footerCard {
                VStack(alignment: .leading, spacing: 4) {
                    footerStatRow(label: "Threads", value: "\(totalThreadCount)", tint: .primary)
                    footerStatRow(label: "Environments", value: "\(sortedRows.count)", tint: .primary)
                    footerStatRow(label: "Running Panes", value: "\(totalRunningPanes)", tint: .primary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
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

    @ViewBuilder
    private func processCell(for row: ActiveWorktreesMonitorRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.processName)
                .font(.body.weight(.medium))
                .lineLimit(1)
            Text("\(row.workspaceName) • \(row.path)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            navigate(to: row.worktree)
        }
        .contextMenu {
            Button("Open Environment") {
                navigate(to: row.worktree)
            }
            Button("Terminate Sessions", role: .destructive) {
                terminateSessions(for: row.worktree)
            }
        }
    }

    private func energyCell(for row: ActiveWorktreesMonitorRow) -> some View {
        Text(String(format: "%.0f", row.energyImpact))
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(energyColor(for: row.energyImpact))
    }

    private func lastAccessedCell(for row: ActiveWorktreesMonitorRow) -> some View {
        Text(row.lastAccessed, format: .dateTime.month(.abbreviated).day().hour().minute())
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private func terminalStateCell(for row: ActiveWorktreesMonitorRow) -> some View {
        let status = row.terminalStatus
        return Text(status.title)
            .font(.caption)
            .foregroundStyle(status.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(status.color.opacity(0.12), in: Capsule())
    }

    private func actionCell(for row: ActiveWorktreesMonitorRow) -> some View {
        HStack(spacing: 8) {
            Button {
                navigate(to: row.worktree)
            } label: {
                Image(systemName: "arrowshape.forward.circle")
            }
            .buttonStyle(.borderless)
            .help("Open environment")

            Button(role: .destructive) {
                terminateSessions(for: row.worktree)
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .help("Terminate sessions")
        }
    }

    @ViewBuilder
    private func footerCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

        if #available(macOS 26.0, *) {
            content()
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    shape
                        .fill(.white.opacity(0.001))
                        .glassEffect(.regular, in: shape)
                )
                .overlay(
                    shape.strokeBorder(.white.opacity(0.08), lineWidth: 1)
                )
        } else {
            content()
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.thinMaterial, in: shape)
                .overlay(
                    shape.strokeBorder(.secondary.opacity(0.16), lineWidth: 1)
                )
        }
    }

    private func footerStatRow(label: String, value: String, tint: Color) -> some View {
        HStack {
            Text("\(label):")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.caption)
                .foregroundStyle(tint)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Nothing to show")
                .font(.title3.weight(.semibold))
            Text("\(selectedMode.title) has no active environments.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private func energyColor(for value: Double) -> Color {
        if value < 25 { return .green }
        if value < 60 { return .orange }
        return .red
    }

}
