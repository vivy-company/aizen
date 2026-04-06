import SwiftUI

extension ActiveWorktreesView {
    var scopePicker: some View {
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

    var selectedModeBinding: Binding<ActiveWorktreesMonitorMode> {
        Binding(
            get: { selectedMode },
            set: { mode in
                selectedMode = mode
                selectedRowID = nil
                updateSortOrder(for: mode)
            }
        )
    }

    var monitorModePicker: some View {
        Picker("Mode", selection: selectedModeBinding) {
            ForEach(ActiveWorktreesMonitorMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize(horizontal: true, vertical: false)
    }

    func updateSortOrder(for mode: ActiveWorktreesMonitorMode) {
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

    func syncScopeIfNeeded() {
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
