//
//  ActiveWorktreesView.swift
//  aizen
//
//  Shows active worktrees and allows quick navigation/termination
//

import SwiftUI
import CoreData
import os.log

struct ActiveWorktreesView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var metrics = ActiveWorktreesMetrics()

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Worktree.lastAccessed, ascending: false)],
        animation: .default
    )
    private var worktrees: FetchedResults<Worktree>

    @AppStorage("terminalSessionPersistence") private var sessionPersistence = false

    @State private var showTerminateAllConfirm = false
    @State private var sidebarSelection: SidebarSelection? = .all

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

    private var resolvedSelection: SidebarSelection {
        sidebarSelection ?? .all
    }

    private var selectedWorktrees: [Worktree] {
        switch resolvedSelection {
        case .all:
            return activeWorktrees
        case .workspace(let id):
            return workspaceGroups.first { $0.workspaceId == id }?.worktrees ?? []
        case .other:
            return workspaceGroups.first { $0.isOther }?.worktrees ?? []
        }
    }

    private var selectionTitle: String {
        switch resolvedSelection {
        case .all:
            return "All Active Worktrees"
        case .workspace(let id):
            return workspaceGroups.first { $0.workspaceId == id }?.name ?? "Workspace"
        case .other:
            return "Unassigned Worktrees"
        }
    }

    private var selectionSubtitle: String {
        let counts = sessionCounts(for: selectedWorktrees)
        if selectedWorktrees.isEmpty {
            return "No active sessions"
        }
        return "\(selectedWorktrees.count) worktrees • \(counts.total) sessions"
    }

    private var worktreeSections: [WorktreeSection] {
        guard !selectedWorktrees.isEmpty else { return [] }

        switch resolvedSelection {
        case .all:
            return workspaceGroups.map { group in
                WorktreeSection(
                    id: group.id,
                    title: group.name,
                    subtitle: "\(group.worktrees.count) worktrees",
                    worktrees: group.worktrees.sorted(by: worktreeSort)
                )
            }
        case .workspace, .other:
            return repositorySections(for: selectedWorktrees)
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .frame(minWidth: 860, minHeight: 540)
        .onAppear { metrics.start() }
        .onDisappear { metrics.stop() }
        .onChange(of: activeWorktreeIDs) { _ in
            syncSelectionIfNeeded()
        }
        .toolbar {
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
                .controlSize(.large)
                .tint(.red)
                .disabled(activeWorktrees.isEmpty)
            }
        }
        .alert("Terminate all sessions?", isPresented: $showTerminateAllConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Terminate All", role: .destructive) {
                terminateAll()
            }
        } message: {
            Text("This will close all chat, terminal, browser, and file sessions in active worktrees.")
        }
    }

    private var sidebar: some View {
        List(selection: $sidebarSelection) {
            Section("Overview") {
                SidebarRow(
                    title: "All Worktrees",
                    subtitle: "\(activeWorktrees.count) active",
                    color: .secondary,
                    worktreeCount: activeWorktrees.count,
                    counts: sessionCounts(for: activeWorktrees)
                )
                .tag(SidebarSelection.all)
            }

            Section("Workspaces") {
                ForEach(workspaceGroups) { group in
                    if group.isOther {
                        SidebarRow(
                            title: group.name,
                            subtitle: "\(group.worktrees.count) worktrees",
                            color: colorFromHex(group.colorHex) ?? .secondary,
                            worktreeCount: group.worktrees.count,
                            counts: sessionCounts(for: group.worktrees)
                        )
                        .tag(SidebarSelection.other)
                    } else if let workspaceId = group.workspaceId {
                        SidebarRow(
                            title: group.name,
                            subtitle: "\(group.worktrees.count) worktrees",
                            color: colorFromHex(group.colorHex) ?? .secondary,
                            worktreeCount: group.worktrees.count,
                            counts: sessionCounts(for: group.worktrees)
                        )
                        .tag(SidebarSelection.workspace(workspaceId))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 220)
    }

    private var detailView: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top) {
                SummaryPills(
                    worktreeCount: selectedWorktrees.count,
                    counts: sessionCounts(for: selectedWorktrees)
                )
                Spacer()
            }
            .padding(.horizontal, 4)

            metricsHeader

            Divider()

            if selectedWorktrees.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(worktreeSections) { section in
                        Section {
                            ForEach(section.worktrees, id: \Worktree.objectID) { worktree in
                                let counts = sessionCounts(for: worktree)
                                ActiveWorktreeRow(
                                    worktree: worktree,
                                    counts: counts,
                                    onOpen: { navigate(to: worktree) },
                                    onTerminate: { terminateSessions(for: worktree) }
                                )
                            }
                        } header: {
                            SectionHeader(title: section.title, subtitle: section.subtitle)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, 16)
        .navigationTitle("Active Worktrees")
        .navigationSubtitle("\(selectionTitle) • \(selectionSubtitle)")
    }

    private var metricsHeader: some View {
        ViewThatFits {
            HStack(spacing: 12) {
                MetricCard(
                    title: "CPU",
                    value: String(format: "%.1f%%", metrics.cpuPercent),
                    subtitle: "App usage",
                    lineColor: .green,
                    history: metrics.cpuHistory.map { $0 / 100.0 }
                )
                MetricCard(
                    title: "Memory",
                    value: metrics.memoryBytes.formattedBytes(),
                    subtitle: "Resident",
                    lineColor: .blue,
                    history: metrics.memoryHistory.map { Double($0) / Double(metrics.maxMemoryHistoryBytes) }
                )
                MetricCard(
                    title: "Energy",
                    value: metrics.energyLabel,
                    subtitle: "Estimated",
                    lineColor: .orange,
                    history: metrics.energyHistory.map { $0 / 100.0 }
                )
            }
            VStack(spacing: 12) {
                MetricCard(
                    title: "CPU",
                    value: String(format: "%.1f%%", metrics.cpuPercent),
                    subtitle: "App usage",
                    lineColor: .green,
                    history: metrics.cpuHistory.map { $0 / 100.0 }
                )
                MetricCard(
                    title: "Memory",
                    value: metrics.memoryBytes.formattedBytes(),
                    subtitle: "Resident",
                    lineColor: .blue,
                    history: metrics.memoryHistory.map { Double($0) / Double(metrics.maxMemoryHistoryBytes) }
                )
                MetricCard(
                    title: "Energy",
                    value: metrics.energyLabel,
                    subtitle: "Estimated",
                    lineColor: .orange,
                    history: metrics.energyHistory.map { $0 / 100.0 }
                )
            }
        }
    }

    private var emptyState: some View {
        Group {
            if #available(macOS 14.0, *) {
                ContentUnavailableView(
                    "No active worktrees",
                    systemImage: "checkmark.seal",
                    description: Text("Open a chat, terminal, or browser session to see it here.")
                )
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("No active worktrees")
                        .font(.headline)
                    Text("Open a chat, terminal, or browser session to see it here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func repositorySections(for worktrees: [Worktree]) -> [WorktreeSection] {
        var buckets: [String: (title: String, worktrees: [Worktree])] = [:]

        for worktree in worktrees {
            let repoName = worktree.repository?.name ?? "Repository"
            let key = worktree.repository?.objectID.uriRepresentation().absoluteString ?? repoName
            if var bucket = buckets[key] {
                bucket.worktrees.append(worktree)
                buckets[key] = bucket
            } else {
                buckets[key] = (title: repoName, worktrees: [worktree])
            }
        }

        return buckets.values
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .map { bucket in
                WorktreeSection(
                    id: bucket.title,
                    title: bucket.title,
                    subtitle: "\(bucket.worktrees.count) worktrees",
                    worktrees: bucket.worktrees.sorted(by: worktreeSort)
                )
            }
    }

    private func worktreeSort(lhs: Worktree, rhs: Worktree) -> Bool {
        let lhsDate = lhs.lastAccessed ?? .distantPast
        let rhsDate = rhs.lastAccessed ?? .distantPast
        if lhsDate != rhsDate { return lhsDate > rhsDate }
        return (lhs.path ?? "").localizedCaseInsensitiveCompare(rhs.path ?? "") == .orderedAscending
    }

    private func syncSelectionIfNeeded() {
        switch resolvedSelection {
        case .all:
            return
        case .other:
            if !workspaceGroups.contains(where: { $0.isOther }) {
                sidebarSelection = .all
            }
        case .workspace(let id):
            if !workspaceGroups.contains(where: { $0.workspaceId == id }) {
                sidebarSelection = .all
            }
        }
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

    private func sessionCounts(for worktrees: [Worktree]) -> SessionCounts {
        worktrees.reduce(SessionCounts()) { result, worktree in
            let counts = sessionCounts(for: worktree)
            return SessionCounts(
                chats: result.chats + counts.chats,
                terminals: result.terminals + counts.terminals,
                browsers: result.browsers + counts.browsers,
                files: result.files + counts.files
            )
        }
    }

    private func colorFromHex(_ hex: String?) -> Color? {
        guard let hex else { return nil }
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitized = sanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&rgb)

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        return Color(red: r, green: g, blue: b)
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
        // Chat sessions
        let chats = (worktree.chatSessions as? Set<ChatSession>) ?? []
        for session in chats where !session.isDeleted {
            if let id = session.id {
                ChatSessionManager.shared.removeAgentSession(for: id)
            }
            viewContext.delete(session)
        }

        // Terminal sessions
        let terminals = (worktree.terminalSessions as? Set<TerminalSession>) ?? []
        for session in terminals where !session.isDeleted {
            if let id = session.id {
                TerminalSessionManager.shared.removeAllTerminals(for: id)
            }
            if sessionPersistence, let layoutJSON = session.splitLayout,
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

        // Browser sessions
        let browsers = (worktree.browserSessions as? Set<BrowserSession>) ?? []
        for session in browsers where !session.isDeleted {
            viewContext.delete(session)
        }

        // File browser session
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

private enum SidebarSelection: Hashable {
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

private struct WorktreeSection: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let worktrees: [Worktree]
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

private struct SidebarRow: View {
    let title: String
    let subtitle: String
    let color: Color
    let worktreeCount: Int
    let counts: SessionCounts

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color.opacity(0.9))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                PillBadge(
                    text: "\(worktreeCount)",
                    color: .secondary,
                    textColor: .primary,
                    backgroundOpacity: 0.12
                )
                if counts.total > 0 {
                    PillBadge(
                        text: "\(counts.total)",
                        color: .secondary,
                        textColor: .primary,
                        backgroundOpacity: 0.12
                    )
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SummaryPills: View {
    let worktreeCount: Int
    let counts: SessionCounts

    var body: some View {
        HStack(spacing: 6) {
            summaryBadge(label: "Worktrees", count: worktreeCount, color: .secondary)
            if counts.chats > 0 { summaryBadge(label: "Chat", count: counts.chats, color: .blue) }
            if counts.terminals > 0 { summaryBadge(label: "Terminal", count: counts.terminals, color: .green) }
            if counts.browsers > 0 { summaryBadge(label: "Browser", count: counts.browsers, color: .orange) }
            if counts.files > 0 { summaryBadge(label: "Files", count: counts.files, color: .teal) }
        }
    }
    
    @ViewBuilder
    private func summaryBadge(label: String, count: Int, color: Color) -> some View {
        PillBadge(
            text: "\(label) \(count)",
            color: color,
            backgroundOpacity: 0.12,
            horizontalPadding: 8,
            verticalPadding: 4
        )
    }
}

private struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private struct ActiveWorktreeRow: View {
    let worktree: Worktree
    let counts: SessionCounts
    let onOpen: () -> Void
    let onTerminate: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(worktreeTitle)
                    .font(.headline)
                    .lineLimit(1)
                Text(worktree.path ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                SessionSummaryRow(counts: counts)
                WorktreeSessionBar(counts: counts)
                    .frame(width: 140)
            }
            Button("Open") {
                onOpen()
            }
            .buttonStyle(.bordered)
            Button("Terminate") {
                onTerminate()
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onOpen()
        }
    }

    private var worktreeTitle: String {
        let repoName = worktree.repository?.name ?? "Worktree"
        if let branch = worktree.branch, !branch.isEmpty {
            return "\(repoName) • \(branch)"
        }
        return repoName
    }
}

private struct SessionSummaryRow: View {
    let counts: SessionCounts

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                sessionChip(title: "Chat", systemImage: "message.fill", count: counts.chats, color: .blue)
                sessionChip(title: "Terminal", systemImage: "terminal.fill", count: counts.terminals, color: .green)
                sessionChip(title: "Browser", systemImage: "safari.fill", count: counts.browsers, color: .orange)
                sessionChip(title: "Files", systemImage: "doc.on.doc.fill", count: counts.files, color: .teal)
            }
            HStack(spacing: 6) {
                sessionChip(title: nil, systemImage: "message.fill", count: counts.chats, color: .blue)
                sessionChip(title: nil, systemImage: "terminal.fill", count: counts.terminals, color: .green)
                sessionChip(title: nil, systemImage: "safari.fill", count: counts.browsers, color: .orange)
                sessionChip(title: nil, systemImage: "doc.on.doc.fill", count: counts.files, color: .teal)
            }
            Text("\(counts.total) sessions")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
    }

    private func sessionChip(title: String?, systemImage: String, count: Int, color: Color) -> some View {
        IconCountPill(
            systemImage: systemImage,
            count: count,
            title: title,
            color: color,
            backgroundOpacity: 0.14
        )
    }
}

private struct WorktreeSessionBar: View {
    let counts: SessionCounts

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let total = max(1, counts.total)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.12))
                HStack(spacing: 0) {
                    segment(counts.chats, total: total, width: width, color: .blue)
                    segment(counts.terminals, total: total, width: width, color: .green)
                    segment(counts.browsers, total: total, width: width, color: .orange)
                    segment(counts.files, total: total, width: width, color: .teal)
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .frame(height: 8)
    }

    private func segment(_ count: Int, total: Int, width: CGFloat, color: Color) -> some View {
        let fraction = CGFloat(count) / CGFloat(total)
        return Rectangle()
            .fill(color)
            .frame(width: width * fraction)
    }
}
