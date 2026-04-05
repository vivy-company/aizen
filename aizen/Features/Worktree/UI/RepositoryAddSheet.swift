//
//  RepositoryAddSheet.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI

enum AddRepositoryMode: CaseIterable {
    case clone
    case existing
    case create

    var title: LocalizedStringKey {
        switch self {
        case .existing:
            return "repository.openExisting"
        case .clone:
            return "repository.cloneFromURL"
        case .create:
            return "repository.createNew"
        }
    }
}

struct RepositoryAddSheet: View {
    @Environment(\.dismiss) var dismiss
    let workspace: Workspace
    @ObservedObject var repositoryManager: WorkspaceRepositoryStore
    var onRepositoryAdded: ((Repository) -> Void)?

    @State var mode: AddRepositoryMode = .existing
    @State var cloneURL = ""
    @State var selectedPath = ""
    @State var repositoryName = ""
    @State var isProcessing = false
    @State var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            DetailHeaderBar(showsBackground: false) {
                Text("repository.add.title", bundle: .main)
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            Divider()

            Form { formContent }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()

            HStack {
                Spacer()

                Button(String(localized: "general.cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(actionButtonText) {
                    addRepository()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing || !isValid)
            }
            .padding()
        }
        .frame(width: 520)
        .frame(minHeight: 360, maxHeight: 560)
        .settingsSheetChrome()
    }
}

#Preview {
    RepositoryAddSheet(
        workspace: Workspace(),
        repositoryManager: WorkspaceRepositoryStore(viewContext: PersistenceController.preview.container.viewContext)
    )
}
