import CoreData
import SwiftUI
import UniformTypeIdentifiers
import os.log

extension WorkspaceSidebarView {
    var workspaceRowFill: Color {
        Color.primary.opacity(0.05)
    }

    var selectedForegroundColor: Color {
        controlActiveState == .key ? .accentColor : .accentColor.opacity(0.78)
    }

    var selectionFillColor: Color {
        let base = NSColor.unemphasizedSelectedContentBackgroundColor
        let alpha: Double = controlActiveState == .key ? 0.26 : 0.18
        return Color(nsColor: base).opacity(alpha)
    }

    func colorFromHex(_ hex: String) -> Color {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        return Color(red: r, green: g, blue: b)
    }

    @ViewBuilder
    var workspacePicker: some View {
        Button {
            showingWorkspaceSwitcher = true
        } label: {
            HStack(spacing: 12) {
                if let workspace = selectedWorkspace {
                    Circle()
                        .fill(colorFromHex(workspace.colorHex ?? "#0000FF"))
                        .frame(width: 10, height: 10)

                    Text(workspace.name ?? String(localized: "workspace.untitled"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .imageScale(.small)
                } else {
                    Text(String(localized: "workspace.untitled"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(workspaceRowFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    var crossProjectRow: some View {
        Button {
            isCrossProjectSelected = true
            selectedRepository = nil
            selectedWorktree = nil
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "square.stack.3d.up.fill")
                    .foregroundStyle(isCrossProjectSelected ? selectedForegroundColor : .secondary)
                    .imageScale(.medium)
                    .frame(width: 18, height: 18)

                Text("Cross-Project")
                    .font(.body)
                    .foregroundStyle(isCrossProjectSelected ? selectedForegroundColor : Color.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)
            }
            .padding(.leading, 8)
            .padding(.trailing, 12)
            .padding(.vertical, 8)
            .background(
                Group {
                    if isCrossProjectSelected {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selectionFillColor)
                    }
                }
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(selectedWorkspace == nil)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    var projectsSectionTitle: some View {
        if selectedWorkspace != nil {
            HStack(spacing: 8) {
                Text("Projects")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 2)
        }
    }
}
