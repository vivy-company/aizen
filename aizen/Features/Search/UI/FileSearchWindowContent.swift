//
//  FileSearchWindowContent.swift
//  aizen
//
//  Created by OpenAI Codex on 04.04.26.
//

import AppKit
import SwiftUI

struct FileSearchWindowContent: View {
    let worktreePath: String
    let onFileSelected: (String) -> Void
    let onClose: () -> Void

    @StateObject private var viewModel: FileSearchStore
    @FocusState private var isSearchFocused: Bool
    @EnvironmentObject private var interaction: PaletteInteractionState
    @State private var hoveredIndex: Int?

    init(worktreePath: String, onFileSelected: @escaping (String) -> Void, onClose: @escaping () -> Void) {
        self.worktreePath = worktreePath
        self.onFileSelected = onFileSelected
        self.onClose = onClose
        self._viewModel = StateObject(wrappedValue: FileSearchStore(worktreePath: worktreePath))
    }

    var body: some View {
        LiquidGlassCard(
            shadowOpacity: 0,
            sheenOpacity: 0.28,
            scrimOpacity: 0.14
        ) {
            VStack(spacing: 0) {
                SpotlightSearchField(
                    placeholder: "Search files…",
                    text: $viewModel.searchQuery,
                    isFocused: $isSearchFocused,
                    onSubmit: {
                        if let result = viewModel.getSelectedResult() {
                            selectFile(result)
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
                .padding(.bottom, 14)

                Divider().opacity(0.25)

                resultsCard

                footer
            }
        }
        .frame(width: 760, height: 520)
        .onAppear {
            viewModel.indexFiles()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSearchFocused = true
            }
        }
        .background {
            Group {
                Button("") {
                    interaction.didUseKeyboard()
                    viewModel.moveSelectionDown()
                }
                .keyboardShortcut(.downArrow, modifiers: [])

                Button("") {
                    interaction.didUseKeyboard()
                    viewModel.moveSelectionUp()
                }
                .keyboardShortcut(.upArrow, modifiers: [])

                Button("") {
                    interaction.didUseKeyboard()
                    if let result = viewModel.getSelectedResult() {
                        selectFile(result)
                    }
                }
                .keyboardShortcut(.return, modifiers: [])

                Button("") { onClose() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .hidden()
        }
    }

    private var resultsCard: some View {
        VStack(spacing: 0) {
            if viewModel.isIndexing {
                indexingView
            } else if viewModel.results.isEmpty {
                emptyResultsView
            } else {
                resultsListView
            }
        }
    }

    private var indexingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text("Indexing...")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
    }

    private var emptyResultsView: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.4))
            Text("No files found")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
    }

    private var resultsListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.results.indices, id: \.self) { index in
                        let result = viewModel.results[index]
                        resultRow(
                            result: result,
                            index: index,
                            isSelected: index == viewModel.selectedIndex,
                            isHovered: hoveredIndex == index
                        )
                        .id(index)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 10)
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .scrollIndicators(.hidden)
            .frame(maxHeight: 380)
            .task(id: viewModel.selectedIndex) {
                proxy.scrollTo(viewModel.selectedIndex, anchor: .center)
            }
        }
    }

    private func resultRow(
        result: FileSearchResult,
        index: Int,
        isSelected: Bool,
        isHovered: Bool
    ) -> some View {
        FileSearchResultRow(
            result: result,
            isSelected: isSelected,
            isHovered: isHovered,
            iconSize: 20,
            spacing: 14,
            titleFont: .system(size: 14, weight: .semibold),
            subtitleFont: .system(size: 12),
            horizontalPadding: 14,
            verticalPadding: 11
        ) {
            Group {
                if isSelected {
                    HStack(spacing: 6) {
                        KeyCap(text: "↩")
                        Text("Open")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } background: { isSelected, isHovered in
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    isSelected ? Color.white.opacity(0.12) :
                        (isHovered ? Color.white.opacity(0.06) : Color.clear)
                )
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                    }
                }
        }
        .onTapGesture {
            selectFile(result)
        }
        .onHover { hovering in
            guard interaction.allowHoverSelection else { return }
            hoveredIndex = hovering ? index : nil
        }
    }

    private func selectFile(_ result: FileSearchResult) {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: result.path, isDirectory: &isDirectory)
        if exists && !isDirectory.boolValue {
            viewModel.trackFileOpen(result.path)
        }
        onFileSelected(result.path)
        onClose()
    }

    private var footer: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                KeyCap(text: "↑")
                KeyCap(text: "↓")
                Text("Navigate")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 6) {
                KeyCap(text: "↩")
                Text("Open")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.clear)
    }
}
