import SwiftUI

extension ActiveWorktreesView {
    @ViewBuilder
    func processCell(for row: ActiveWorktreesMonitorRow) -> some View {
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

    func energyCell(for row: ActiveWorktreesMonitorRow) -> some View {
        Text(String(format: "%.0f", row.energyImpact))
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(energyColor(for: row.energyImpact))
    }

    func lastAccessedCell(for row: ActiveWorktreesMonitorRow) -> some View {
        Text(row.lastAccessed, format: .dateTime.month(.abbreviated).day().hour().minute())
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    func terminalStateCell(for row: ActiveWorktreesMonitorRow) -> some View {
        let status = row.terminalStatus
        return Text(status.title)
            .font(.caption)
            .foregroundStyle(status.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(status.color.opacity(0.12), in: Capsule())
    }

    func actionCell(for row: ActiveWorktreesMonitorRow) -> some View {
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

    func energyColor(for value: Double) -> Color {
        if value < 25 { return .green }
        if value < 60 { return .orange }
        return .red
    }
}
