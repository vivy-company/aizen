//
//  DiffView.swift
//  aizen
//
//  NSTableView-based diff renderer for git changes
//

import SwiftUI
import AppKit

// MARK: - Custom Table View with Copy Support

class DiffTableView: NSTableView {
    weak var coordinator: DiffView.Coordinator?

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "c" {
            copy(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    @objc func copy(_ sender: Any?) {
        guard let coordinator = coordinator else { return }
        let selectedContent = coordinator.getSelectedContent()
        guard !selectedContent.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(selectedContent, forType: .string)
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(copy(_:)) {
            return selectedRowIndexes.count > 0
        }
        return super.validateUserInterfaceItem(item)
    }
}

struct DiffView: NSViewRepresentable {
    // Input mode 1: Raw diff string (for multi-file view)
    private let diffOutput: String?

    // Input mode 2: Pre-parsed lines (for single-file view)
    private let preloadedLines: [DiffLine]?

    let fontSize: Double
    let fontFamily: String
    let repoPath: String
    let showFileHeaders: Bool
    let scrollToFile: String?
    let onFileVisible: ((String) -> Void)?
    let onOpenFile: ((String) -> Void)?
    let commentedLines: Set<String>
    let onAddComment: ((DiffLine, String) -> Void)?

    // Init for raw diff output (used by GitChangesOverlayView)
    init(
        diffOutput: String,
        fontSize: Double,
        fontFamily: String,
        repoPath: String = "",
        scrollToFile: String? = nil,
        onFileVisible: ((String) -> Void)? = nil,
        onOpenFile: ((String) -> Void)? = nil,
        commentedLines: Set<String> = [],
        onAddComment: ((DiffLine, String) -> Void)? = nil
    ) {
        self.diffOutput = diffOutput
        self.preloadedLines = nil
        self.fontSize = fontSize
        self.fontFamily = fontFamily
        self.repoPath = repoPath
        self.showFileHeaders = true
        self.scrollToFile = scrollToFile
        self.onFileVisible = onFileVisible
        self.onOpenFile = onOpenFile
        self.commentedLines = commentedLines
        self.onAddComment = onAddComment
    }

    // Init for pre-parsed lines (used by FileDiffSectionView)
    init(
        lines: [DiffLine],
        fontSize: Double,
        fontFamily: String,
        repoPath: String = "",
        showFileHeaders: Bool = false,
        commentedLines: Set<String> = [],
        onAddComment: ((DiffLine, String) -> Void)? = nil
    ) {
        self.diffOutput = nil
        self.preloadedLines = lines
        self.fontSize = fontSize
        self.fontFamily = fontFamily
        self.repoPath = repoPath
        self.showFileHeaders = showFileHeaders
        self.scrollToFile = nil
        self.onFileVisible = nil
        self.onOpenFile = nil
        self.commentedLines = commentedLines
        self.onAddComment = onAddComment
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let tableView = DiffTableView()
        tableView.coordinator = context.coordinator

        tableView.style = .plain
        tableView.headerView = nil
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.selectionHighlightStyle = .regular
        tableView.allowsMultipleSelection = true
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.backgroundColor = .clear
        tableView.allowsColumnReordering = false
        tableView.allowsColumnResizing = false
        tableView.allowsColumnSelection = false
        tableView.usesAutomaticRowHeights = true
        tableView.gridStyleMask = []
        tableView.gridColor = .clear

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("diff"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.backgroundColor = .clear
        scrollView.drawsBackground = false

        context.coordinator.tableView = tableView
        context.coordinator.repoPath = repoPath
        context.coordinator.showFileHeaders = showFileHeaders
        context.coordinator.setupScrollObserver(for: scrollView)

        if let lines = preloadedLines {
            context.coordinator.loadLines(lines, fontSize: fontSize, fontFamily: fontFamily)
        } else if let output = diffOutput {
            context.coordinator.parseAndReload(diffOutput: output, fontSize: fontSize, fontFamily: fontFamily)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onFileVisible = onFileVisible
        context.coordinator.onOpenFile = onOpenFile
        context.coordinator.repoPath = repoPath
        context.coordinator.showFileHeaders = showFileHeaders
        context.coordinator.onAddComment = onAddComment

        let commentedLinesChanged = context.coordinator.commentedLines != commentedLines
        context.coordinator.commentedLines = commentedLines

        if let lines = preloadedLines {
            context.coordinator.loadLines(lines, fontSize: fontSize, fontFamily: fontFamily)
        } else if let output = diffOutput {
            context.coordinator.parseAndReload(diffOutput: output, fontSize: fontSize, fontFamily: fontFamily)
        }

        // Refresh cells if commented lines changed
        if commentedLinesChanged {
            context.coordinator.tableView?.reloadData()
        }

        // Handle scroll to file request
        if let file = scrollToFile, file != context.coordinator.lastScrolledFile {
            context.coordinator.scrollToFile(file)
            context.coordinator.lastScrolledFile = file
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            repoPath: repoPath,
            showFileHeaders: showFileHeaders,
            onOpenFile: onOpenFile,
            commentedLines: commentedLines,
            onAddComment: onAddComment
        )
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource {
        weak var tableView: NSTableView?
        var rows: [DiffRow] = []
        var rowHeight: CGFloat = 20
        var fontSize: Double = 12
        var fontFamily: String = "Menlo"
        var repoPath: String = ""
        var showFileHeaders: Bool = true
        var onFileVisible: ((String) -> Void)?
        var onOpenFile: ((String) -> Void)?
        var lastScrolledFile: String?
        var commentedLines: Set<String> = []
        var onAddComment: ((DiffLine, String) -> Void)?

        private var lastDataHash: Int = 0
        private var fileRowIndices: [String: Int] = [:]
        private var rowToFilePath: [Int: String] = [:]
        private var lastVisibleFile: String?
        private var scrollObserver: NSObjectProtocol?
        private var rawLines: [String] = []
        private var parsedRows: [Int: DiffRow] = [:]
        private var lineParser: DiffLineParser?
        private var parseTask: Task<ParsedDiffMetadata, Never>?

        enum DiffRow {
            case fileHeader(path: String)
            case line(DiffLine)
            case lazyLine(rawIndex: Int)
        }

        private enum RowKind: Sendable {
            case fileHeader(path: String)
            case lazyLine(rawIndex: Int)
        }

        private struct ParsedDiffMetadata: Sendable {
            let rawLines: [String]
            let rowKinds: [RowKind]
            let fileRowIndices: [String: Int]
            let rowToFilePath: [Int: String]
        }

        init(
            repoPath: String,
            showFileHeaders: Bool,
            onOpenFile: ((String) -> Void)?,
            commentedLines: Set<String>,
            onAddComment: ((DiffLine, String) -> Void)?
        ) {
            self.repoPath = repoPath
            self.showFileHeaders = showFileHeaders
            self.onOpenFile = onOpenFile
            self.commentedLines = commentedLines
            self.onAddComment = onAddComment
            super.init()
        }

        deinit {
            if let observer = scrollObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            parseTask?.cancel()
        }

        func setupScrollObserver(for scrollView: NSScrollView) {
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                self?.updateVisibleFile()
            }
            scrollView.contentView.postsBoundsChangedNotifications = true
        }

        private func updateVisibleFile() {
            guard let tableView = tableView else { return }
            let visibleRect = tableView.visibleRect

            let firstVisibleRow = max(0, tableView.row(at: NSPoint(x: 0, y: visibleRect.minY + 1)))
            guard firstVisibleRow >= 0, firstVisibleRow < rows.count else { return }

            var file = rowToFilePath[firstVisibleRow]

            if file == nil {
                let lastVisibleRow = min(rows.count - 1, max(firstVisibleRow, tableView.row(at: NSPoint(x: 0, y: visibleRect.maxY - 1))))
                if lastVisibleRow >= firstVisibleRow {
                    for row in firstVisibleRow...lastVisibleRow {
                        if let path = rowToFilePath[row] {
                            file = path
                            break
                        }
                    }
                }
            }

            if file == nil, firstVisibleRow > 0 {
                for row in stride(from: firstVisibleRow - 1, through: 0, by: -1) {
                    if let path = rowToFilePath[row] {
                        file = path
                        break
                    }
                }
            }

            if let file, file != lastVisibleFile {
                lastVisibleFile = file
                onFileVisible?(file)
            }
        }

        func scrollToFile(_ file: String) {
            guard let tableView = tableView,
                  let rowIndex = fileRowIndices[file] else { return }

            tableView.scrollRowToVisible(rowIndex)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                let rowRect = tableView.rect(ofRow: rowIndex)
                tableView.enclosingScrollView?.contentView.scroll(to: NSPoint(x: 0, y: rowRect.minY))
            }
        }

        // Load pre-parsed DiffLine array
        func loadLines(_ lines: [DiffLine], fontSize: Double, fontFamily: String) {
            let newHash = lines.hashValue ^ fontSize.hashValue ^ fontFamily.hashValue
            guard newHash != lastDataHash else { return }

            lastDataHash = newHash
            self.fontSize = fontSize
            self.fontFamily = fontFamily

            let font = NSFont(name: fontFamily, size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            rowHeight = ceil(font.ascender - font.descender + font.leading) + 6

            rows = lines.map { .line($0) }
            tableView?.reloadData()
        }

        // Parse raw diff output - store raw lines for lazy parsing
        func parseAndReload(diffOutput: String, fontSize: Double, fontFamily: String) {
            let newHash = diffOutput.hashValue ^ fontSize.hashValue ^ fontFamily.hashValue
            guard newHash != lastDataHash else { return }

            lastDataHash = newHash
            self.fontSize = fontSize
            self.fontFamily = fontFamily

            let font = NSFont(name: fontFamily, size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            rowHeight = ceil(font.ascender - font.descender + font.leading) + 6

            parseTask?.cancel()
            let showFileHeaders = self.showFileHeaders

            let task = Task.detached(priority: .utility) {
                Self.parseDiffOutput(diffOutput: diffOutput, showFileHeaders: showFileHeaders)
            }
            parseTask = task

            Task { @MainActor [weak self] in
                guard let self else { return }
                let parsed = await task.value
                guard !Task.isCancelled, self.lastDataHash == newHash else { return }

                self.rawLines = parsed.rawLines
                self.lineParser = DiffLineParser(rawLines: parsed.rawLines)

                self.parsedRows.removeAll(keepingCapacity: true)
                self.fileRowIndices = parsed.fileRowIndices
                self.rowToFilePath = parsed.rowToFilePath
                self.rows = parsed.rowKinds.map { kind in
                    switch kind {
                    case .fileHeader(let path):
                        return .fileHeader(path: path)
                    case .lazyLine(let rawIndex):
                        return .lazyLine(rawIndex: rawIndex)
                    }
                }

                self.tableView?.reloadData()
            }
        }

        private static func parseDiffOutput(diffOutput: String, showFileHeaders: Bool) -> ParsedDiffMetadata {
            var rawLines: [String] = []
            rawLines.reserveCapacity(max(128, diffOutput.count / 48))
            diffOutput.enumerateLines { line, _ in
                rawLines.append(line)
            }

            var rowKinds: [RowKind] = []
            rowKinds.reserveCapacity(rawLines.count)

            var fileRowIndices: [String: Int] = [:]
            var rowToFilePath: [Int: String] = [:]

            var rowIndex = 0
            var currentFilePath: String?

            for (lineIndex, line) in rawLines.enumerated() {
                if line.hasPrefix("diff --git ") {
                    currentFilePath = parseFilePathFromDiffHeader(line)
                    if showFileHeaders, let path = currentFilePath, !path.isEmpty {
                        fileRowIndices[path] = rowIndex
                        rowKinds.append(.fileHeader(path: path))
                        rowToFilePath[rowIndex] = path
                        rowIndex += 1
                    }
                    continue
                }

                if line.hasPrefix("--- ") ||
                    line.hasPrefix("+++ ") ||
                    line.hasPrefix("index ") ||
                    line.hasPrefix("new file") ||
                    line.hasPrefix("deleted file") ||
                    line.hasPrefix("similarity index") ||
                    line.hasPrefix("rename from") ||
                    line.hasPrefix("rename to") {
                    continue
                }

                guard let firstChar = line.first else { continue }

                if firstChar == "@" || firstChar == "+" || firstChar == "-" || firstChar == " " {
                    rowKinds.append(.lazyLine(rawIndex: lineIndex))
                    if let path = currentFilePath {
                        rowToFilePath[rowIndex] = path
                    }
                    rowIndex += 1
                }
            }

            return ParsedDiffMetadata(
                rawLines: rawLines,
                rowKinds: rowKinds,
                fileRowIndices: fileRowIndices,
                rowToFilePath: rowToFilePath
            )
        }

        private static func parseFilePathFromDiffHeader(_ line: String) -> String? {
            // Format: "diff --git a/<path> b/<path>"
            let parts = line.split(separator: " ")
            guard parts.count >= 4 else { return nil }
            let bPart = parts[3]
            if bPart.hasPrefix("b/") {
                return String(bPart.dropFirst(2))
            }
            return String(bPart)
        }

        func getRow(at index: Int) -> DiffRow {
            guard index < rows.count else {
                return .line(DiffLine(lineNumber: 0, oldLineNumber: nil, newLineNumber: nil, content: "", type: .context))
            }

            switch rows[index] {
            case .lazyLine(let rawIndex):
                if let cached = parsedRows[index] {
                    return cached
                }
                let parsed = DiffRow.line(lineParser?.parseLine(at: rawIndex) ?? DiffLine(lineNumber: rawIndex, oldLineNumber: nil, newLineNumber: nil, content: "", type: .context))
                parsedRows[index] = parsed
                return parsed
            default:
                return rows[index]
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            rows.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < rows.count else { return nil }

            let resolvedRow = getRow(at: row)
            switch resolvedRow {
            case .fileHeader(let path):
                return makeFileHeaderCell(path: path, tableView: tableView)
            case .line(let diffLine):
                return makeLineCell(diffLine: diffLine, row: row, tableView: tableView)
            case .lazyLine:
                return nil
            }
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            guard row < rows.count else { return nil }
            let rowView = DiffNSRowView()

            let resolvedRow = getRow(at: row)
            switch resolvedRow {
            case .fileHeader:
                rowView.lineType = nil
            case .line(let diffLine):
                rowView.lineType = diffLine.type
            case .lazyLine:
                rowView.lineType = .context
            }

            return rowView
        }

        private func makeFileHeaderCell(path: String, tableView: NSTableView) -> NSView {
            let id = NSUserInterfaceItemIdentifier("FileHeader")
            if let cell = tableView.makeView(withIdentifier: id, owner: nil) as? FileHeaderCellView {
                cell.configure(path: path, repoPath: repoPath, fontSize: fontSize, fontFamily: fontFamily, onOpenFile: onOpenFile)
                return cell
            }
            let cell = FileHeaderCellView(identifier: id)
            cell.configure(path: path, repoPath: repoPath, fontSize: fontSize, fontFamily: fontFamily, onOpenFile: onOpenFile)
            return cell
        }

        private func makeLineCell(diffLine: DiffLine, row: Int, tableView: NSTableView) -> NSView {
            let id = NSUserInterfaceItemIdentifier("DiffLine")
            let filePath = rowToFilePath[row] ?? ""
            let commentKey = "\(filePath):\(diffLine.lineNumber)"
            let hasComment = commentedLines.contains(commentKey)

            let cell: LineCellView
            if let existingCell = tableView.makeView(withIdentifier: id, owner: nil) as? LineCellView {
                cell = existingCell
            } else {
                cell = LineCellView(identifier: id)
            }

            cell.configure(
                diffLine: diffLine,
                fontSize: fontSize,
                fontFamily: fontFamily,
                hasComment: hasComment,
                onCommentTap: { [weak self] in
                    self?.onAddComment?(diffLine, filePath)
                }
            )
            return cell
        }

        func getSelectedContent() -> String {
            guard let tableView = tableView else { return "" }
            var lines: [String] = []
            for rowIndex in tableView.selectedRowIndexes {
                let row = getRow(at: rowIndex)
                switch row {
                case .fileHeader(let path):
                    lines.append("--- \(path) ---")
                case .line(let diffLine):
                    let marker = diffLine.type.marker
                    lines.append("\(marker)\(diffLine.content)")
                case .lazyLine:
                    break
                }
            }
            return lines.joined(separator: "\n")
        }
    }
}
