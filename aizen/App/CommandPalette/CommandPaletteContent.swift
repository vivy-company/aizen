//
//  CommandPaletteContent.swift
//  aizen
//
//  SwiftUI content for the command palette panel.
//

import CoreData
import SwiftUI

struct CommandPaletteContent: View {
    let onNavigate: (CommandPaletteNavigationAction) -> Void
    let onClose: () -> Void
    @ObservedObject var viewModel: WorktreeSearchViewModel
    @ObservedObject var workspaceGraphQueryController: WorkspaceGraphQueryController

    @Environment(\.managedObjectContext) var viewContext

    @FocusState var isSearchFocused: Bool
    @EnvironmentObject var interaction: PaletteInteractionState
    @State var hoveredIndex: Int?
    @AppStorage("selectedWorktreeId") var currentWorktreeId: String?

    var body: some View {
        LiquidGlassCard(
            shadowOpacity: 0,
            sheenOpacity: 0.28,
            scrimOpacity: 0.14
        ) {
            VStack(spacing: 0) {
                SpotlightSearchField(
                    placeholder: placeholderText(for: viewModel.scope),
                    text: $viewModel.searchQuery,
                    isFocused: $isSearchFocused,
                    onSubmit: {
                        if let action = viewModel.selectedNavigationAction() {
                            handleSelection(action)
                        }
                    },
                    onEscape: onClose,
                    trailing: {
                        Button(action: onClose) {
                            KeyCap(text: "esc")
                        }
                        .buttonStyle(.plain)
                        .help("Close")
                    }
                )
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 10)

                scopeChips
                    .padding(.horizontal, 18)
                    .padding(.bottom, 12)

                Divider().opacity(0.25)

                if activeResultsEmpty {
                    emptyResultsView
                } else {
                    resultsList
                }

                footer
            }
        }
        .frame(width: 760, height: 520)
        .modifier(CommandPaletteLifecycleModifier(content: self))
        .modifier(CommandPaletteKeyboardShortcutModifier(content: self))
    }
}
