//
//  ContentView+Sheets.swift
//  aizen
//
//  Created by Codex on 2026-04-03.
//

import SwiftUI

extension ContentView {
    func withPresentationSheets<Content: View>(_ content: Content) -> some View {
        content
            .sheet(isPresented: $showingAddRepository) {
                if let workspace = selectionStore.selectedWorkspace ?? workspaces.first {
                    RepositoryAddSheet(
                        workspace: workspace,
                        repositoryManager: repositoryManager,
                        onRepositoryAdded: { repository in
                            selectRepository(repository)
                        }
                    )
                }
            }
            .sheet(isPresented: $showingOnboarding) {
                OnboardingView()
            }
            .sheet(isPresented: $showingCrossProjectOnboarding) {
                CrossProjectOnboardingView()
            }
    }
}
