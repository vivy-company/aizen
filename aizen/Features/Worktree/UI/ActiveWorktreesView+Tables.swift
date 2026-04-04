import SwiftUI

extension ActiveWorktreesView {
    var chatsTable: some View {
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

    var terminalsTable: some View {
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

    var filesTable: some View {
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

    var browsersTable: some View {
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
}
