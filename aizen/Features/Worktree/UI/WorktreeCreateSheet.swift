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
        sheetContent
    }
}

#Preview {
    WorktreeCreateSheet(
        repository: Repository(),
        repositoryManager: WorkspaceRepositoryStore(viewContext: PersistenceController.preview.container.viewContext)
    )
}
