//
//  WorkspaceSwitcherSheet.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 24.11.25.
//

import SwiftUI

struct WorkspaceSwitcherSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var repositoryManager: RepositoryManager

    let workspaces: [Workspace]
    @Binding var selectedWorkspace: Workspace?

    @State private var hoveredWorkspace: Workspace?
    @State private var workspaceToEdit: Workspace?
    @State private var showingNewWorkspace = false

    private func colorFromHex(_ hex: String) -> Color {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        return Color(red: r, green: g, blue: b)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            DetailHeaderBar(
                showsBackground: false,
                padding: EdgeInsets(top: 20, leading: 20, bottom: 16, trailing: 20)
            ) {
                Text("workspace.switcher.title")
                    .font(.title2)
                    .fontWeight(.semibold)
            } trailing: {
                DetailCloseButton { dismiss() }
            }

            Divider()

            // Workspace list
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(workspaces, id: \.id) { workspace in
                        WorkspaceRow(
                            workspace: workspace,
                            isSelected: selectedWorkspace?.id == workspace.id,
                            isHovered: hoveredWorkspace?.id == workspace.id,
                            colorFromHex: colorFromHex,
                            onSelect: {
                                selectedWorkspace = workspace
                                dismiss()
                            },
                            onEdit: {
                                workspaceToEdit = workspace
                            }
                        )
                        .onHover { hovering in
                            hoveredWorkspace = hovering ? workspace : nil
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }

            Divider()

            // Footer with new workspace button
            HStack {
                Button {
                    showingNewWorkspace = true
                } label: {
                    Label("workspace.new", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
        .frame(width: 400, height: 500)
        .sheet(item: $workspaceToEdit) { workspace in
            WorkspaceEditSheet(workspace: workspace, repositoryManager: repositoryManager)
        }
        .sheet(isPresented: $showingNewWorkspace) {
            WorkspaceCreateSheet(repositoryManager: repositoryManager)
        }
    }
}

#Preview {
    WorkspaceSwitcherSheet(
        repositoryManager: RepositoryManager(viewContext: PersistenceController.preview.container.viewContext),
        workspaces: [],
        selectedWorkspace: .constant(nil)
    )
}
