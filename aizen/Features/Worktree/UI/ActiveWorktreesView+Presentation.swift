import SwiftUI

extension ActiveWorktreesView {
    var footer: some View {
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

    @ViewBuilder
    func footerCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
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

    func footerStatRow(label: String, value: String, tint: Color) -> some View {
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

    var emptyState: some View {
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

    func energyColor(for value: Double) -> Color {
        if value < 25 { return .green }
        if value < 60 { return .orange }
        return .red
    }
}
