//
//  WorkspaceCreateSheet.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI

struct WorkspaceCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
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
                Text("workspace.create.title", bundle: .main)
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            Divider()

            ScrollView {
                formContent
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
        .settingsSheetChrome()
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
        repositoryManager: WorkspaceRepositoryStore(viewContext: PersistenceController.preview.container.viewContext)
    )
}
