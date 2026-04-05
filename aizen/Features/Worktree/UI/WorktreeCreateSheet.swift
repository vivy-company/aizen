//
//  WorktreeCreateSheet.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI

enum EnvironmentCreationMode: String, CaseIterable {
    case linked
    case independent

    var title: String {
        switch self {
        case .linked:
            return "Linked (Git Environment)"
        case .independent:
            return "Independent (Clone/Copy)"
        }
    }
}

struct WorktreeCreateSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var repository: Repository
    @ObservedObject var repositoryManager: WorkspaceRepositoryStore

    @State var mode: EnvironmentCreationMode = .linked
    @State var environmentName = ""
    @State var branchName = ""
    @State var selectedBranch: BranchInfo?
    @State var isProcessing = false
    @State var errorMessage: String?
    @State var validationWarning: String?
    @State var showingBranchSelector = false
    @State var selectedTemplateIndex: Int?
    @State var showingPostCreateActions = false
    @State var shouldRunPostCreateActions = true
    @State var independentMethod: WorkspaceRepositoryStore.IndependentEnvironmentMethod = .clone
    @State var detectedSubmodules: [GitSubmoduleInfo] = []
    @State var loadingSubmodules = false
    @State var initializeSubmodules = true
    @State var includeNestedSubmodules = true
    @State var selectedSubmodulePaths: Set<String> = []
    @State var matchSubmoduleBranchToEnvironment = false

    @AppStorage("branchNameTemplates") var branchNameTemplatesData: Data = Data()

    var body: some View {
        VStack(spacing: 0) {
            DetailHeaderBar(showsBackground: false) {
                Text("Create Environment")
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            Divider()

            Form {
                environmentTypeSection
                namingSection

                if mode == .linked {
                    linkedModeSections
                } else {
                    independentModeSections
                }

                postCreateActionsSection

                if let error = errorMessage {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.callout)
                                Text("Environment creation failed")
                                    .font(.callout)
                                    .fontWeight(.semibold)
                            }
                            Text(error)
                                .font(.system(.caption, design: .monospaced))
                        }
                        .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()

            HStack {
                Spacer()

                Button(String(localized: "worktree.create.cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Create Environment") {
                    createEnvironment()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing || !isValid)
            }
            .padding()
        }
        .frame(width: 520)
        .frame(minHeight: 420, maxHeight: 560)
        .settingsSheetChrome()
        .sheet(isPresented: $showingBranchSelector) {
            BranchSelectorView(
                repository: repository,
                repositoryManager: repositoryManager,
                selectedBranch: $selectedBranch
            )
        }
        .sheet(isPresented: $showingPostCreateActions) {
            PostCreateActionsSheet(repository: repository)
        }
        .onAppear {
            suggestEnvironmentName()
            if !isGitProject {
                mode = .independent
                independentMethod = .copy
            }
            loadSubmodules()
        }
    }

}

#Preview {
    WorktreeCreateSheet(
        repository: Repository(),
        repositoryManager: WorkspaceRepositoryStore(viewContext: PersistenceController.preview.container.viewContext)
    )
}
