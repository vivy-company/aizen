//
//  WorkspaceCreateSheet.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI

struct WorkspaceCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
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
            DetailHeaderBar(showsBackground: false) {
                Text("workspace.create.title", bundle: .main)
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("workspace.create.name", bundle: .main)
                            .font(.headline)

                        TextField(String(localized: "workspace.create.namePlaceholder"), text: $workspaceName)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("workspace.create.color", bundle: .main)
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
            }

            Divider()

            // Footer
            HStack {
                Spacer()

                Button(String(localized: "general.cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(String(localized: "workspace.create.create")) {
                    createWorkspace()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(workspaceName.isEmpty)
            }
            .padding()
        }
        .frame(width: 450)
        .frame(minHeight: 250, maxHeight: 400)
    }

    private func createWorkspace() {
        do {
            let colorHex = selectedColor.toHex()
            _ = try repositoryManager.createWorkspace(name: workspaceName, colorHex: colorHex)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    WorkspaceCreateSheet(
        repositoryManager: RepositoryManager(viewContext: PersistenceController.preview.container.viewContext)
    )
}
