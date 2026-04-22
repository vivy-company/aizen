import SwiftUI

struct ProjectSearchWindowContent: View {
    @ObservedObject var viewModel: ProjectSearchStore
    let onOpen: (SearchOpenRequest) -> Void
    let onClose: () -> Void

    @FocusState private var isSearchFocused: Bool
    @EnvironmentObject private var interaction: PaletteInteractionState
    @State private var hoveredIndex: Int?

    init(
        viewModel: ProjectSearchStore,
        onOpen: @escaping (SearchOpenRequest) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onOpen = onOpen
        self.onClose = onClose
    }

    var body: some View {
        LiquidGlassCard(
            shadowOpacity: 0,
            sheenOpacity: 0.28,
            scrimOpacity: 0.14
        ) {
            VStack(spacing: 0) {
                header
                controls

                Divider().opacity(0.25)

                searchBody

                footer
            }
        }
        .frame(width: 980, height: 620)
        .onAppear {
            viewModel.onAppear()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSearchFocused = true
            }
        }
        .onChange(of: viewModel.mode) { _, _ in
            hoveredIndex = nil
            DispatchQueue.main.async {
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
                    openSelectedResult()
                }
                .keyboardShortcut(.return, modifiers: [])

                Button("") {
                    interaction.didUseKeyboard()
                    viewModel.switchMode()
                }
                .keyboardShortcut(.tab, modifiers: [])

                Button("") { onClose() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .hidden()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            SpotlightSearchField(
                placeholder: LocalizedStringKey(viewModel.mode.placeholder),
                text: $viewModel.searchQuery,
                isFocused: $isSearchFocused,
                onSubmit: openSelectedResult,
                onEscape: onClose,
                trailing: {
                    EmptyView()
                }
            )

            Picker("", selection: $viewModel.mode) {
                ForEach(ProjectSearchMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)

            Button(action: onClose) {
                KeyCap(text: "esc")
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            if viewModel.mode == .content {
                Picker("", selection: $viewModel.grepMode) {
                    ForEach(ProjectSearchGrepMode.allCases) { grepMode in
                        Text(grepMode.title).tag(grepMode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.resultsSummaryText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                if let statusText = viewModel.statusText {
                    Text(statusText)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if let regexFallbackError = viewModel.regexFallbackError {
                Label("Regex fallback", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.orange.opacity(0.12))
                    )
                    .help(regexFallbackError)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    private var searchBody: some View {
        HStack(spacing: 0) {
            resultsPane
                .frame(width: 420)

            Divider().opacity(0.25)

            previewPane
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultsPane: some View {
        VStack(spacing: 0) {
            if viewModel.isSearching && viewModel.results.isEmpty {
                loadingView
            } else if viewModel.results.isEmpty {
                emptyResultsView
            } else {
                resultsListView
            }

            if viewModel.canLoadMore {
                Divider().opacity(0.25)

                Button(action: viewModel.loadMore) {
                    HStack(spacing: 8) {
                        if viewModel.isLoadingMore {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 12, weight: .medium))
                        }
                        Text(viewModel.isLoadingMore ? "Loading more…" : "Load more matches")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text(viewModel.mode == .files ? "Searching files…" : "Searching file contents…")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 50)
    }

    private var emptyResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: viewModel.emptyStateSymbolName)
                .font(.system(size: 30))
                .foregroundStyle(.secondary.opacity(0.5))

            Text(viewModel.emptyStateTitle)
                .font(.system(size: 14, weight: .semibold))

            Text(viewModel.emptyStateMessage)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }

    private var resultsListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(viewModel.results.enumerated()), id: \.element.id) { index, result in
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: viewModel.selectedIndex) {
                proxy.scrollTo(viewModel.selectedIndex, anchor: .center)
            }
        }
    }

    private func resultRow(
        result: ProjectSearchResult,
        index: Int,
        isSelected: Bool,
        isHovered: Bool
    ) -> some View {
        ProjectSearchResultRow(
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
            viewModel.selectResult(at: index)
        }
        .onTapGesture(count: 2) {
            viewModel.selectResult(at: index)
            openSelectedResult()
        }
        .onHover { hovering in
            guard interaction.allowHoverSelection else { return }
            hoveredIndex = hovering ? index : nil
        }
    }

    private var previewPane: some View {
        VStack(spacing: 0) {
            previewHeader

            Divider().opacity(0.25)

            previewContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var previewHeader: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(previewTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                if let previewSubtitle {
                    Text(previewSubtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let locationLabel = selectedLocationLabel {
                Text(locationLabel)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var previewContent: some View {
        switch viewModel.previewState {
        case .idle(let message):
            previewPlaceholder(
                symbolName: "doc.text.magnifyingglass",
                title: "Preview",
                message: message
            )

        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading preview…")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .loaded(let preview):
            CodeEditorView(
                content: preview.content,
                language: detectLanguage(from: preview.path),
                filePath: preview.path,
                selectionRequest: preview.openRequest,
                shouldFocusOnAppear: false
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .unavailable(let message):
            previewPlaceholder(
                symbolName: "eye.slash",
                title: "Preview unavailable",
                message: message
            )
        }
    }

    private func previewPlaceholder(
        symbolName: String,
        title: String,
        message: String
    ) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbolName)
                .font(.system(size: 28))
                .foregroundStyle(.secondary.opacity(0.5))

            Text(title)
                .font(.system(size: 14, weight: .semibold))

            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }

    private func openSelectedResult() {
        guard let request = viewModel.activateSelection() else { return }
        onOpen(request)
        onClose()
    }

    private var previewTitle: String {
        switch viewModel.previewState {
        case .loaded(let preview):
            return preview.relativePath
        default:
            return viewModel.selectedResult?.relativePath ?? "Preview"
        }
    }

    private var previewSubtitle: String? {
        guard let selectedResult = viewModel.selectedResult else { return nil }

        switch selectedResult {
        case .file:
            return selectedResult.path
        case .content(let result):
            return result.lineContent.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private var selectedLocationLabel: String? {
        guard case .content(let result)? = viewModel.selectedResult else { return nil }
        return "L\(result.lineNumber):\(result.column)"
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
                KeyCap(text: "⇥")
                Text("Switch")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

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

    private func detectLanguage(from path: String) -> String? {
        let ext = (path as NSString).pathExtension.lowercased()
        return ext.isEmpty ? nil : ext
    }
}
