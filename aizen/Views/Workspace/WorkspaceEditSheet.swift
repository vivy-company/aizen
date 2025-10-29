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
    @ObservedObject var repositoryManager: RepositoryManager

    @State private var workspaceName = ""
    @State private var selectedColor: Color = .blue
    @State private var errorMessage: String?

    let availableColors: [Color] = [
        .blue, .purple, .pink, .red, .orange, .yellow, .green, .teal, .cyan, .indigo
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("workspace.edit.title", bundle: .main)
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()
            }
            .padding()

            Divider()

            // Content
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("workspace.create.name", bundle: .main)
                        .font(.headline)

                    TextField(String(localized: "workspace.create.namePlaceholder"), text: $workspaceName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            if !workspaceName.isEmpty {
                                saveChanges()
                            }
                        }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("workspace.edit.color", bundle: .main)
                        .font(.headline)

                    HStack(spacing: 12) {
                        ForEach(availableColors, id: \.self) { color in
                            Circle()
                                .fill(color)
                                .frame(width: 30, height: 30)
                                .overlay {
                                    if selectedColor == color {
                                        Circle()
                                            .strokeBorder(.white, lineWidth: 3)
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.white)
                                            .font(.caption)
                                    }
                                }
                                .onTapGesture {
                                    selectedColor = color
                                }
                        }
                    }
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding()

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
        .onAppear {
            print("DEBUG: Editing workspace - name: \(workspace.name ?? "nil"), colorHex: \(workspace.colorHex ?? "nil")")
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

    private func saveChanges() {
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
        repositoryManager: RepositoryManager(viewContext: PersistenceController.preview.container.viewContext)
    )
}
