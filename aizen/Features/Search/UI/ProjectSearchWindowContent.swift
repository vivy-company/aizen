import SwiftUI

struct ProjectSearchWindowContent: View {
    @ObservedObject var viewModel: ProjectSearchStore
    let onOpen: (SearchOpenRequest) -> Void
    let onClose: () -> Void
    let onResizeRequest: ((ProjectSearchMode) -> Void)?

    @FocusState private var isSearchFocused: Bool
    @EnvironmentObject private var interaction: PaletteInteractionState
    @State private var hoveredResultID: String?

    static let filesWidth: CGFloat = 700
    static let filesHeight: CGFloat = 480
    static let contentWidth: CGFloat = 1060
    static let contentHeight: CGFloat = 620

    init(
        viewModel: ProjectSearchStore,
        onOpen: @escaping (SearchOpenRequest) -> Void,
        onClose: @escaping () -> Void,
        onResizeRequest: ((ProjectSearchMode) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.onOpen = onOpen
        self.onClose = onClose
        self.onResizeRequest = onResizeRequest
    }

    var body: some View {
        LiquidGlassCard(
            shadowOpacity: 0,
            sheenOpacity: 0.28,
            scrimOpacity: 0.14
        ) {
            VStack(spacing: 0) {
                header

                Divider().opacity(0.25)

                searchBody

                footer
            }
        }
        .frame(
            width: viewModel.mode == .files ? Self.filesWidth : Self.contentWidth,
            height: viewModel.mode == .files ? Self.filesHeight : Self.contentHeight
        )
        .animation(.easeInOut(duration: 0.2), value: viewModel.mode)
        .onAppear {
            viewModel.onAppear()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSearchFocused = true
            }
        }
        .onChange(of: viewModel.mode) { _, newMode in
            hoveredResultID = nil
            onResizeRequest?(newMode)
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

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            SpotlightSearchField(
                placeholder: LocalizedStringKey(viewModel.mode.placeholder),
                text: $viewModel.searchQuery,
                isFocused: $isSearchFocused,
                onSubmit: openSelectedResult,
                onEscape: onClose,
                trailing: { searchFieldTrailing }
            )

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

    @ViewBuilder
    private var searchFieldTrailing: some View {
        HStack(spacing: 8) {
            if viewModel.mode == .content {
                regexToggle
            }

            summaryBadge

            if let regexFallbackError = viewModel.regexFallbackError {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)
                    .help(regexFallbackError)
            }
        }
    }

    private var regexToggle: some View {
        Button {
            viewModel.grepMode = viewModel.grepMode == .regex ? .plain : .regex
        } label: {
            Text(".*")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(viewModel.grepMode == .regex ? .white : .secondary)
                .frame(width: 28, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(viewModel.grepMode == .regex ? Color.accentColor : Color.white.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
        .help(viewModel.grepMode == .regex ? "Plain text search" : "Regex search")
    }

    @ViewBuilder
    private var summaryBadge: some View {
        if viewModel.totalMatched > 0 || viewModel.isSearching {
            Text(viewModel.isSearching && viewModel.results.isEmpty ? "…" : "\(viewModel.totalMatched)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
        }
    }

    // MARK: - Body

    private var searchBody: some View {
        Group {
            if viewModel.mode == .files {
                filesBody
            } else {
                contentBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filesBody: some View {
        resultsListOrPlaceholder
    }

    private var contentBody: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                resultsListOrPlaceholder

                if viewModel.canLoadMore {
                    Divider().opacity(0.25)
                    loadMoreButton
                }
            }
            .frame(width: 440)

            Divider().opacity(0.25)

            previewPane
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsListOrPlaceholder: some View {
        if viewModel.isSearching && viewModel.results.isEmpty {
            loadingView
        } else if viewModel.results.isEmpty {
            emptyResultsView
        } else {
            resultsListView
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text(viewModel.mode == .files ? "Searching files…" : "Searching contents…")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 50)
    }

    private var emptyResultsView: some View {
        VStack(spacing: 10) {
            Image(systemName: viewModel.emptyStateSymbolName)
                .font(.system(size: 26))
                .foregroundStyle(.secondary.opacity(0.4))

            Text(viewModel.emptyStateTitle)
                .font(.system(size: 13, weight: .semibold))

            Text(viewModel.emptyStateMessage)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }

    private var resultsListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.results) { result in
                        resultRow(
                            result: result,
                            isSelected: result.id == viewModel.selectedResultID,
                            isHovered: hoveredResultID == result.id
                        )
                        .id(result.id)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 8)
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: viewModel.selectedResultID) {
                guard let selectedResultID = viewModel.selectedResultID else { return }
                proxy.scrollTo(selectedResultID, anchor: .center)
            }
        }
    }

    private func resultRow(
        result: ProjectSearchResult,
        isSelected: Bool,
        isHovered: Bool
    ) -> some View {
        ProjectSearchResultRow(
            result: result,
            isSelected: isSelected,
            isHovered: isHovered,
            iconSize: 18,
            spacing: 12,
            titleFont: .system(size: 13, weight: .semibold),
            subtitleFont: .system(size: 11),
            horizontalPadding: 12,
            verticalPadding: 9
        ) {
            EmptyView()
        } background: { isSelected, isHovered in
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    isSelected ? Color.white.opacity(0.10) :
                        (isHovered ? Color.white.opacity(0.05) : Color.clear)
                )
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    }
                }
        }
        .onTapGesture {
            viewModel.selectResult(id: result.id)
        }
        .onTapGesture(count: 2) {
            viewModel.selectResult(id: result.id)
            openSelectedResult()
        }
        .onHover { hovering in
            guard interaction.allowHoverSelection else { return }
            if hovering {
                hoveredResultID = result.id
            } else if hoveredResultID == result.id {
                hoveredResultID = nil
            }
        }
    }

    private var loadMoreButton: some View {
        Button(action: viewModel.loadMore) {
            HStack(spacing: 6) {
                if viewModel.isLoadingMore {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 11, weight: .medium))
                }
                Text(viewModel.isLoadingMore ? "Loading…" : "More results")
                    .font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    // MARK: - Preview (content mode only)

    private var previewPane: some View {
        VStack(spacing: 0) {
            previewHeader
            Divider().opacity(0.25)
            previewContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var previewHeader: some View {
        HStack(spacing: 8) {
            Text(previewTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()

            if let locationLabel = selectedLocationLabel {
                Text(locationLabel)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
            }

            if viewModel.selectedResult != nil {
                Button(action: openSelectedResult) {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                .help("Open in Files")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var previewContent: some View {
        switch viewModel.previewState {
        case .idle(let message):
            previewPlaceholder(
                symbolName: "doc.text.magnifyingglass",
                message: message
            )

        case .loading:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .loaded(let preview):
            ProjectSearchPreviewView(preview: preview)

        case .unavailable(let message):
            previewPlaceholder(
                symbolName: "eye.slash",
                message: message
            )
        }
    }

    private func previewPlaceholder(
        symbolName: String,
        message: String
    ) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbolName)
                .font(.system(size: 24))
                .foregroundStyle(.secondary.opacity(0.3))

            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 220)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                KeyCap(text: "↑")
                KeyCap(text: "↓")
            }

            Text("navigate")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)

            Spacer()

            if let statusText = viewModel.statusText {
                Text(statusText)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            KeyCap(text: "⇥")
            Text(viewModel.mode == .files ? "content" : "files")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)

            KeyCap(text: "↩")
            Text("open")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

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

    private var selectedLocationLabel: String? {
        guard case .content(let result)? = viewModel.selectedResult else { return nil }
        return "L\(result.lineNumber):\(result.column)"
    }
}
