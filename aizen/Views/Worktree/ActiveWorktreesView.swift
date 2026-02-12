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
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var metrics = ActiveWorktreesMetrics()

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Worktree.lastAccessed, ascending: false)],
        animation: .default
    )
    private var worktrees: FetchedResults<Worktree>

    @AppStorage("terminalSessionPersistence") private var sessionPersistence = false

    @State private var searchText = ""
    @State private var selectedMode: MonitorMode = .chats
    @State private var selectedScope: ScopeSelection = .all
    @State private var selectedRowID: MonitorRow.ID?
    @State private var showTerminateAllConfirm = false
    @State private var sortOrder: [KeyPathComparator<MonitorRow>] = [
        KeyPathComparator(\.chatSessions, order: .reverse),
        KeyPathComparator(\.lastAccessed, order: .reverse)
    ]

    private var surfaceColor: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    private var activeWorktrees: [Worktree] {
        worktrees.filter { worktree in
            guard !worktree.isDeleted else { return false }
            return isActive(worktree)
        }
    }

    private var activeWorktreeIDs: [NSManagedObjectID] {
        activeWorktrees.map { $0.objectID }
    }

    private var workspaceGroups: [WorkspaceGroup] {
        var groups: [NSManagedObjectID: WorkspaceGroup] = [:]
        var otherWorktrees: [Worktree] = []

        for worktree in activeWorktrees {
            guard let workspace = worktree.repository?.workspace, !workspace.isDeleted else {
                otherWorktrees.append(worktree)
                continue
            }

            let id = workspace.objectID
            if var existing = groups[id] {
                existing.worktrees.append(worktree)
                groups[id] = existing
            } else {
                groups[id] = WorkspaceGroup(
                    id: id.uriRepresentation().absoluteString,
                    workspaceId: id,
                    name: workspace.name ?? "Workspace",
                    colorHex: workspace.colorHex,
                    order: Int(workspace.order),
                    worktrees: [worktree],
                    isOther: false
                )
            }
        }

        var sorted = groups.values.sorted { lhs, rhs in
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        if !otherWorktrees.isEmpty {
            sorted.append(
                WorkspaceGroup(
                    id: "other",
                    workspaceId: nil,
                    name: "Other",
                    colorHex: nil,
                    order: Int.max,
                    worktrees: otherWorktrees,
                    isOther: true
                )
            )
        }

        return sorted
    }

    private var scopedWorktrees: [Worktree] {
        switch selectedScope {
        case .all:
            return activeWorktrees
        case .workspace(let id):
            return workspaceGroups.first { $0.workspaceId == id }?.worktrees ?? []
        case .other:
            return workspaceGroups.first { $0.isOther }?.worktrees ?? []
        }
    }

    private var filteredWorktrees: [Worktree] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return scopedWorktrees.sorted(by: worktreeSort)
        }

        return scopedWorktrees.filter { worktree in
            let workspaceName = worktree.repository?.workspace?.name ?? ""
            let repositoryName = worktree.repository?.name ?? ""
            let branch = worktree.branch ?? ""
            let path = worktree.path ?? ""

            return workspaceName.localizedCaseInsensitiveContains(query) ||
                repositoryName.localizedCaseInsensitiveContains(query) ||
                branch.localizedCaseInsensitiveContains(query) ||
                path.localizedCaseInsensitiveContains(query)
        }
        .sorted(by: worktreeSort)
    }

    private var monitorRows: [MonitorRow] {
        let seeds = filteredWorktrees.map(buildSeed(for:))
        guard !seeds.isEmpty else { return [] }

        let scores = seeds.map(activityScore(for:))
        let scoreTotal = max(scores.reduce(0, +), 0.001)

        var rows: [MonitorRow] = []
        rows.reserveCapacity(seeds.count)

        for index in seeds.indices {
            let seed = seeds[index]
            let score = scores[index]
            let cpuShare = min(
                99.9,
                max(
                    0,
                    (metrics.cpuPercent * (score / scoreTotal)) + Double(seed.runtime.runningPanes) * 0.35
                )
            )

            let estimatedMemory = UInt64(max(
                64_000_000,
                130_000_000 +
                    (seed.counts.chats * 50_000_000) +
                    (seed.counts.terminals * 88_000_000) +
                    (seed.counts.browsers * 120_000_000) +
                    (seed.counts.files * 20_000_000) +
                    (seed.runtime.livePanes * 28_000_000)
            ))

            let energyImpact = min(
                100,
                (cpuShare * 1.3) +
                    Double(seed.runtime.runningPanes * 8) +
                    Double(seed.counts.total)
            )

            let threads = max(
                1,
                (seed.counts.total * 4) +
                    (seed.runtime.livePanes * 14) +
                    (seed.runtime.runningPanes * 6)
            )

            let idleWakeUps = Int((energyImpact * 1.8).rounded()) + (threads / 3)

            rows.append(
                MonitorRow(
                    id: seed.id,
                    worktree: seed.worktree,
                    processName: seed.processName,
                    workspaceName: seed.workspaceName,
                    path: seed.path,
                    cpuPercent: cpuShare,
                    memoryBytes: estimatedMemory,
                    energyImpact: energyImpact,
                    threadCount: threads,
                    idleWakeUps: idleWakeUps,
                    totalSessions: seed.counts.total,
                    counts: seed.counts,
                    runtime: seed.runtime,
                    lastAccessed: seed.lastAccessed
                )
            )
        }

        return rows
    }

    private var visibleRows: [MonitorRow] {
        monitorRows.filter(rowMatchesSelectedMode)
    }

    private var sortedRows: [MonitorRow] {
        var rows = visibleRows
        rows.sort(using: sortOrder)
        return rows
    }

    private var totalThreadCount: Int {
        sortedRows.reduce(0) { $0 + $1.threadCount }
    }

    private var totalRunningPanes: Int {
        sortedRows.reduce(0) { $0 + $1.runtime.runningPanes }
    }

    private var scopeLabel: String {
        switch selectedScope {
        case .all:
            return "All Environments"
        case .workspace(let id):
            return workspaceGroups.first(where: { $0.workspaceId == id })?.name ?? "Workspace"
        case .other:
            return "Other"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            content
            Divider()
            footer
        }
        .frame(minWidth: 940, minHeight: 560)
        .background(surfaceColor)
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
        .onChange(of: activeWorktreeIDs) { _, _ in
            syncScopeIfNeeded()
        }
        .onChange(of: selectedMode) { _, mode in
            selectedRowID = nil
            updateSortOrder(for: mode)
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
            Text("All Environments").tag(ScopeSelection.all)
            ForEach(workspaceGroups) { group in
                if group.isOther {
                    Text("Other").tag(ScopeSelection.other)
                } else if let workspaceId = group.workspaceId {
                    Text(group.name).tag(ScopeSelection.workspace(workspaceId))
                }
            }
        }
        .pickerStyle(.menu)
    }

    private var monitorModePicker: some View {
        Picker("Mode", selection: $selectedMode) {
            ForEach(MonitorMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private func processCell(for row: MonitorRow) -> some View {
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

    private func energyCell(for row: MonitorRow) -> some View {
        Text(String(format: "%.0f", row.energyImpact))
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(energyColor(for: row.energyImpact))
    }

    private func lastAccessedCell(for row: MonitorRow) -> some View {
        Text(row.lastAccessed, format: .dateTime.month(.abbreviated).day().hour().minute())
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private func terminalStateCell(for row: MonitorRow) -> some View {
        let status = row.terminalStatus
        return Text(status.title)
            .font(.caption)
            .foregroundStyle(status.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(status.color.opacity(0.12), in: Capsule())
    }

    private func actionCell(for row: MonitorRow) -> some View {
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

    private func buildSeed(for worktree: Worktree) -> MonitorRowSeed {
        let counts = sessionCounts(for: worktree)
        let runtime = terminalRuntime(for: worktree)
        let repository = worktree.repository?.name ?? "Environment"
        let branch = worktree.branch?.isEmpty == false ? worktree.branch! : "detached"

        return MonitorRowSeed(
            id: worktree.objectID.uriRepresentation().absoluteString,
            worktree: worktree,
            processName: "\(repository) • \(branch)",
            workspaceName: worktree.repository?.workspace?.name ?? "Other",
            path: worktree.path ?? "",
            counts: counts,
            runtime: runtime,
            lastAccessed: worktree.lastAccessed ?? .distantPast
        )
    }

    private func activityScore(for seed: MonitorRowSeed) -> Double {
        let minutesSinceAccess = max(0, Date().timeIntervalSince(seed.lastAccessed) / 60)
        let recency = max(0.25, min(1.0, 1.15 - (minutesSinceAccess / 240.0)))

        let sessionWeight =
            (Double(seed.counts.chats) * 0.8) +
            (Double(seed.counts.terminals) * 2.0) +
            (Double(seed.counts.browsers) * 1.4) +
            (Double(seed.counts.files) * 0.4)

        let runtimeWeight =
            (Double(seed.runtime.livePanes) * 0.8) +
            (Double(seed.runtime.runningPanes) * 1.8)

        return max(0.2, (sessionWeight + runtimeWeight + 0.4) * recency)
    }

    private func updateSortOrder(for mode: MonitorMode) {
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

    private func rowMatchesSelectedMode(_ row: MonitorRow) -> Bool {
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

    private func worktreeSort(lhs: Worktree, rhs: Worktree) -> Bool {
        let lhsDate = lhs.lastAccessed ?? .distantPast
        let rhsDate = rhs.lastAccessed ?? .distantPast
        if lhsDate != rhsDate { return lhsDate > rhsDate }
        return (lhs.path ?? "").localizedCaseInsensitiveCompare(rhs.path ?? "") == .orderedAscending
    }

    private func isActive(_ worktree: Worktree) -> Bool {
        chatCount(for: worktree) > 0 ||
            terminalCount(for: worktree) > 0 ||
            browserCount(for: worktree) > 0 ||
            fileCount(for: worktree) > 0
    }

    private func chatCount(for worktree: Worktree) -> Int {
        let sessions = (worktree.chatSessions as? Set<ChatSession>) ?? []
        return sessions.filter { !$0.isDeleted }.count
    }

    private func terminalCount(for worktree: Worktree) -> Int {
        let sessions = (worktree.terminalSessions as? Set<TerminalSession>) ?? []
        return sessions.filter { !$0.isDeleted }.count
    }

    private func browserCount(for worktree: Worktree) -> Int {
        let sessions = (worktree.browserSessions as? Set<BrowserSession>) ?? []
        return sessions.filter { !$0.isDeleted }.count
    }

    private func fileCount(for worktree: Worktree) -> Int {
        if let session = worktree.fileBrowserSession, !session.isDeleted {
            return 1
        }
        return 0
    }

    private func sessionCounts(for worktree: Worktree) -> SessionCounts {
        SessionCounts(
            chats: chatCount(for: worktree),
            terminals: terminalCount(for: worktree),
            browsers: browserCount(for: worktree),
            files: fileCount(for: worktree)
        )
    }

    private func terminalRuntime(for worktree: Worktree) -> TerminalRuntimeSnapshot {
        let terminalSessions = ((worktree.terminalSessions as? Set<TerminalSession>) ?? [])
            .filter { !$0.isDeleted }

        var expectedPanes = 0
        var livePanes = 0
        var runningPanes = 0

        for session in terminalSessions {
            guard let sessionId = session.id else {
                expectedPanes += 1
                continue
            }

            var paneIds = paneIDs(for: session)
            if paneIds.isEmpty {
                paneIds = TerminalSessionManager.shared.paneIds(for: sessionId)
            }

            let uniquePaneIds = Array(Set(paneIds))
            if uniquePaneIds.isEmpty {
                expectedPanes += 1
                continue
            }

            expectedPanes += uniquePaneIds.count
            let runtimeCounts = TerminalSessionManager.shared.runtimeCounts(for: sessionId, paneIds: uniquePaneIds)
            livePanes += runtimeCounts.livePanes
            runningPanes += runtimeCounts.runningPanes
        }

        return TerminalRuntimeSnapshot(
            expectedPanes: expectedPanes,
            livePanes: livePanes,
            runningPanes: runningPanes
        )
    }

    private func paneIDs(for session: TerminalSession) -> [String] {
        if let layoutJSON = session.splitLayout,
           let layout = SplitLayoutHelper.decode(layoutJSON) {
            return layout.allPaneIds()
        }

        if let focusedPaneId = session.focusedPaneId,
           !focusedPaneId.isEmpty {
            return [focusedPaneId]
        }

        return []
    }

    private func navigate(to worktree: Worktree) {
        guard let repo = worktree.repository,
              let workspace = repo.workspace,
              let workspaceId = workspace.id,
              let repoId = repo.id,
              let worktreeId = worktree.id else {
            return
        }

        NotificationCenter.default.post(
            name: .navigateToWorktree,
            object: nil,
            userInfo: [
                "workspaceId": workspaceId,
                "repoId": repoId,
                "worktreeId": worktreeId
            ]
        )
    }

    private func terminateAll() {
        for worktree in activeWorktrees {
            terminateSessions(for: worktree)
        }
    }

    private func terminateSessions(for worktree: Worktree) {
        let chats = (worktree.chatSessions as? Set<ChatSession>) ?? []
        for session in chats where !session.isDeleted {
            if let id = session.id {
                ChatSessionManager.shared.removeAgentSession(for: id)
            }
            viewContext.delete(session)
        }

        let terminals = (worktree.terminalSessions as? Set<TerminalSession>) ?? []
        for session in terminals where !session.isDeleted {
            if let id = session.id {
                TerminalSessionManager.shared.removeAllTerminals(for: id)
            }

            if sessionPersistence,
               let layoutJSON = session.splitLayout,
               let layout = SplitLayoutHelper.decode(layoutJSON) {
                let paneIds = layout.allPaneIds()
                Task {
                    for paneId in paneIds {
                        await TmuxSessionManager.shared.killSession(paneId: paneId)
                    }
                }
            }

            viewContext.delete(session)
        }

        let browsers = (worktree.browserSessions as? Set<BrowserSession>) ?? []
        for session in browsers where !session.isDeleted {
            viewContext.delete(session)
        }

        if let session = worktree.fileBrowserSession, !session.isDeleted {
            viewContext.delete(session)
        }

        do {
            try viewContext.save()
        } catch {
            Logger.workspace.error("Failed to terminate sessions: \(error.localizedDescription)")
        }
    }
}

private enum MonitorMode: String, CaseIterable, Identifiable {
    case chats
    case terminals
    case files
    case browsers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chats: return "Chats"
        case .terminals: return "Terminals"
        case .files: return "Files"
        case .browsers: return "Browsers"
        }
    }

    var tintColor: Color {
        switch self {
        case .chats: return .blue
        case .terminals: return .green
        case .files: return .orange
        case .browsers: return .teal
        }
    }
}

private enum ScopeSelection: Hashable {
    case all
    case workspace(NSManagedObjectID)
    case other
}

private struct WorkspaceGroup: Identifiable {
    let id: String
    let workspaceId: NSManagedObjectID?
    let name: String
    let colorHex: String?
    let order: Int
    var worktrees: [Worktree]
    let isOther: Bool
}

private struct SessionCounts {
    var chats: Int = 0
    var terminals: Int = 0
    var browsers: Int = 0
    var files: Int = 0

    var total: Int {
        chats + terminals + browsers + files
    }
}

private struct MonitorRowSeed {
    let id: String
    let worktree: Worktree
    let processName: String
    let workspaceName: String
    let path: String
    let counts: SessionCounts
    let runtime: TerminalRuntimeSnapshot
    let lastAccessed: Date
}

private struct MonitorRow: Identifiable {
    let id: String
    let worktree: Worktree
    let processName: String
    let workspaceName: String
    let path: String
    let cpuPercent: Double
    let memoryBytes: UInt64
    let energyImpact: Double
    let threadCount: Int
    let idleWakeUps: Int
    let totalSessions: Int
    let counts: SessionCounts
    let runtime: TerminalRuntimeSnapshot
    let lastAccessed: Date

    var chatSessions: Int { counts.chats }
    var terminalSessions: Int { counts.terminals }
    var fileSessions: Int { counts.files }
    var browserSessions: Int { counts.browsers }
    var runningPanes: Int { runtime.runningPanes }
    var livePanes: Int { runtime.livePanes }
    var terminalStateSortOrder: Int {
        switch terminalStatus {
        case .running: return 3
        case .ready: return 2
        case .detached: return 1
        case .none: return 0
        }
    }

    var terminalStatus: TerminalState {
        if counts.terminals == 0 {
            return .none
        }

        if runtime.runningPanes > 0 {
            return .running
        }

        if runtime.livePanes > 0 {
            return .ready
        }

        if runtime.expectedPanes > 0 {
            return .detached
        }

        return .none
    }
}

private struct TerminalRuntimeSnapshot {
    let expectedPanes: Int
    let livePanes: Int
    let runningPanes: Int
}

private enum TerminalState {
    case running
    case ready
    case detached
    case none

    var title: String {
        switch self {
        case .running: return "Running"
        case .ready: return "Ready"
        case .detached: return "Detached"
        case .none: return "None"
        }
    }

    var color: Color {
        switch self {
        case .running: return .green
        case .ready: return .blue
        case .detached: return .orange
        case .none: return .secondary
        }
    }
}
