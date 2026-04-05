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
}
