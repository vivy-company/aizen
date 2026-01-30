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

    @State private var gitChangesContext: GitChangesContext?
    @State private var gitPanelController: GitPanelWindowController?
    @State private var showingLicenseDeepLinkSheet = false
    @StateObject private var repositoryManager: RepositoryManager

    // Persist open Git panel worktree for restoration
    @AppStorage("openGitPanelWorktreeURI") private var openGitPanelWorktreeURI: String = ""

    init(context: NSManagedObjectContext) {
        self.context = context
        _repositoryManager = StateObject(wrappedValue: RepositoryManager(viewContext: context))
    }

    var body: some View {
        ContentView(
            context: context,
            repositoryManager: repositoryManager,
            gitChangesContext: $gitChangesContext
        )
        .onAppear {
            restoreGitPanelIfNeeded()
            if LicenseManager.shared.hasPendingDeepLink {
                showingLicenseDeepLinkSheet = true
            }
        }
        .onChange(of: gitChangesContext) { _, newContext in
            if let ctx = newContext, !ctx.worktree.isDeleted {
                // Close existing window if any
                gitPanelController?.close()

                // Persist worktree URI for restoration
                openGitPanelWorktreeURI = ctx.worktree.objectID.uriRepresentation().absoluteString

                // Create and show new window
                gitPanelController = GitPanelWindowController(
                    context: ctx,
                    repositoryManager: repositoryManager,
                    onClose: {
                        openGitPanelWorktreeURI = ""
                        gitChangesContext = nil
                        gitPanelController = nil
                    }
                )
                gitPanelController?.showWindow(nil)
            } else if newContext == nil {
                // Close window when context is cleared
                openGitPanelWorktreeURI = ""
                gitPanelController?.close()
                gitPanelController = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openLicenseDeepLink)) { _ in
            showingLicenseDeepLinkSheet = true
        }
        .sheet(isPresented: $showingLicenseDeepLinkSheet) {
            LicenseDeepLinkSheet(
                licenseManager: LicenseManager.shared,
                onOpenSettings: {
                    SettingsWindowManager.shared.show()
                    NotificationCenter.default.post(name: .openSettingsPro, object: nil)
                }
            )
        }
    }

    private func restoreGitPanelIfNeeded() {
        guard !openGitPanelWorktreeURI.isEmpty,
              let url = URL(string: openGitPanelWorktreeURI),
              let objectID = context.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: url),
              let worktree = try? context.existingObject(with: objectID) as? Worktree,
              !worktree.isDeleted,
              let path = worktree.path else {
            // Clear invalid URI
            openGitPanelWorktreeURI = ""
            return
        }

        // Recreate the Git panel context
        let service = GitRepositoryService(worktreePath: path)
        gitChangesContext = GitChangesContext(worktree: worktree, service: service)
    }
}

// Context for git changes sheet
struct GitChangesContext: Identifiable, Equatable {
    let id = UUID()
    let worktree: Worktree
    let service: GitRepositoryService

    static func == (lhs: GitChangesContext, rhs: GitChangesContext) -> Bool {
        lhs.id == rhs.id
    }
}
