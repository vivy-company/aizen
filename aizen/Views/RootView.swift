//
//  RootView.swift
//  aizen
//
//  Root view that handles full-window overlays above the toolbar
//

import SwiftUI
import CoreData

struct RootView: View {
    let context: NSManagedObjectContext

    @State private var showingGitChanges = false
    @State private var gitChangesWorktree: Worktree?
    @StateObject private var repositoryManager: RepositoryManager

    init(context: NSManagedObjectContext) {
        self.context = context
        _repositoryManager = StateObject(wrappedValue: RepositoryManager(viewContext: context))
    }

    var body: some View {
        GeometryReader { geometry in
            ContentView(
                context: context,
                repositoryManager: repositoryManager,
                showingGitChanges: $showingGitChanges,
                gitChangesWorktree: $gitChangesWorktree
            )
            .sheet(isPresented: $showingGitChanges) {
                if let worktree = gitChangesWorktree,
                   let repository = worktree.repository, !worktree.isDeleted {
                    GitChangesOverlayContainer(
                        worktree: worktree,
                        repository: repository,
                        repositoryManager: repositoryManager,
                        showingGitChanges: $showingGitChanges
                    )
                    .frame(
                        minWidth: max(900, geometry.size.width - 100),
                        idealWidth: geometry.size.width - 40,
                        minHeight: max(500, geometry.size.height - 100),
                        idealHeight: geometry.size.height - 40
                    )
                }
            }
        }
    }
}
