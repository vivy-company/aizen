//
//  WorkspaceEditSheet.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI

struct WorkspaceEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var workspace: Workspace
    @ObservedObject var repositoryManager: WorkspaceRepositoryStore

    @State var workspaceName = ""
    @State var selectedColor: Color = .blue
    @State var errorMessage: String?

    let availableColors: [Color] = [
        .blue, .purple, .pink, .red, .orange, .yellow, .green, .teal, .cyan, .indigo
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            DetailHeaderBar(showsBackground: false) {
                Text("workspace.edit.title", bundle: .main)
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            Divider()

            formContent

            Spacer()

            Divider()

            // Footer
            HStack {
                Spacer()

                Button(String(localized: "general.cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(String(localized: "workspace.edit.save")) {
                    saveChanges()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(workspaceName.isEmpty)
            }
            .padding()
        }
        .frame(width: 450)
        .frame(minHeight: 280, maxHeight: 400)
        .settingsSheetChrome()
        .onAppear {
            workspaceName = workspace.name ?? ""
            if let colorHex = workspace.colorHex {
                selectedColor = colorFromHex(colorHex)
            } else {
                selectedColor = .blue
            }
        }
    }

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

    func saveChanges() {
        do {
            let colorHex = selectedColor.toHex()
            try repositoryManager.updateWorkspace(workspace, name: workspaceName, colorHex: colorHex)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension Color {
    func toHex() -> String {
        guard let components = NSColor(self).cgColor.components else { return "#0000FF" }

        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)

        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

#Preview {
    WorkspaceEditSheet(
        workspace: Workspace(),
        repositoryManager: WorkspaceRepositoryStore(viewContext: PersistenceController.preview.container.viewContext)
    )
}
