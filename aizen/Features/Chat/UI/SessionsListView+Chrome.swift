//
//  SessionsListView+Chrome.swift
//  aizen
//

import SwiftUI

extension View {
    func sessionsListChrome(_ screen: SessionsListView) -> some View {
        self
            .toolbarBackground(screen.surfaceColor, for: .windowToolbar)
            .toolbarBackground(.visible, for: .windowToolbar)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Picker("", selection: Binding(
                        get: { screen.viewModel.selectedFilter },
                        set: { screen.viewModel.selectedFilter = $0 }
                    )) {
                        Label("All", systemImage: "square.grid.2x2").tag(SessionsListStore.SessionFilter.all)
                        Label("Active", systemImage: "bolt.fill").tag(SessionsListStore.SessionFilter.active)
                        Label("Archived", systemImage: "archivebox").tag(SessionsListStore.SessionFilter.archived)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                ToolbarItem(placement: .navigation) {
                    Spacer().frame(width: 12)
                }

                ToolbarItem(placement: .navigation) {
                    screen.agentFilterMenu
                }
            }
            .searchable(
                text: Binding(
                    get: { screen.viewModel.searchText },
                    set: { screen.viewModel.searchText = $0 }
                ),
                placement: .toolbar,
                prompt: "Search sessions"
            )
            .alert(
                "Error",
                isPresented: Binding(
                    get: { screen.viewModel.errorMessage != nil },
                    set: { if !$0 { screen.viewModel.errorMessage = nil } }
                )
            ) {
                Button("OK") {
                    screen.viewModel.errorMessage = nil
                }
            } message: {
                if let errorMessage = screen.viewModel.errorMessage {
                    Text(errorMessage)
                }
            }
    }
}
