//  SelectableDiffView.swift
//  aizen
//
//  NSTableView-based diff renderer with multiline selection support for chat

import SwiftUI
import AppKit

// MARK: - Custom Table View with Copy Support

private class ChatDiffTableView: NSTableView {
    weak var coordinator: SelectableDiffView.Coordinator?

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

// MARK: - Row View

private class ChatDiffRowView: NSTableRowView {
    var lineType: ChatDiffLineType?

    override func drawBackground(in dirtyRect: NSRect) {
        guard let type = lineType else {
            NSColor.clear.setFill()
            bounds.fill()
            return
        }
        type.backgroundColor.setFill()
        bounds.fill()
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
        bounds.fill()
        NSColor.controlAccentColor.setFill()
        NSRect(x: 0, y: 0, width: 3, height: bounds.height).fill()
    }

    override var interiorBackgroundStyle: NSView.BackgroundStyle {
        .normal
    }
}

// MARK: - Line Cell

private class ChatDiffLineCell: NSTableCellView {
    private let markerLabel = NSTextField(labelWithString: "")
    private let contentLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) { nil }

    private func setupViews() {
        markerLabel.translatesAutoresizingMaskIntoConstraints = false
        markerLabel.alignment = .left

        contentLabel.translatesAutoresizingMaskIntoConstraints = false
        contentLabel.lineBreakMode = .byClipping
        contentLabel.maximumNumberOfLines = 1
        contentLabel.isSelectable = true
        contentLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        addSubview(markerLabel)
        addSubview(contentLabel)

        NSLayoutConstraint.activate([
            markerLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            markerLabel.widthAnchor.constraint(equalToConstant: 14),
            markerLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            contentLabel.leadingAnchor.constraint(equalTo: markerLabel.trailingAnchor, constant: 2),
            contentLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            contentLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    func configure(line: ChatDiffLine, fontSize: Double, fontFamily: String) {
        let font = NSFont(name: fontFamily, size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)

        markerLabel.stringValue = line.type.marker
        markerLabel.font = font
        markerLabel.textColor = line.type.markerColor

        contentLabel.stringValue = line.content.isEmpty ? " " : line.content
        contentLabel.font = font
        contentLabel.textColor = line.type.textColor
    }
}

// MARK: - Types

enum ChatDiffLineType {
    case context
    case added
    case deleted
    case separator

    var marker: String {
        switch self {
        case .context: return " "
        case .added: return "+"
        case .deleted: return "-"
        case .separator: return "@"
        }
    }

    var markerColor: NSColor {
        switch self {
        case .context: return .secondaryLabelColor
        case .added: return .systemGreen
        case .deleted: return .systemRed
        case .separator: return .systemCyan
        }
    }

    var textColor: NSColor {
        switch self {
        case .context: return .secondaryLabelColor
        case .added: return .systemGreen
        case .deleted: return .systemRed
        case .separator: return .systemCyan
        }
    }

    var backgroundColor: NSColor {
        switch self {
        case .context: return .clear
        case .added: return NSColor.systemGreen.withAlphaComponent(0.1)
        case .deleted: return NSColor.systemRed.withAlphaComponent(0.1)
        case .separator: return .clear
        }
    }
}

struct ChatDiffLine: Identifiable {
    let id = UUID()
    let type: ChatDiffLineType
    let content: String
}

// MARK: - SelectableDiffView

struct SelectableDiffView: NSViewRepresentable {
    let lines: [ChatDiffLine]
    let fontSize: Double
    let fontFamily: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let tableView = ChatDiffTableView()
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
        context.coordinator.updateData(lines: lines, fontSize: fontSize, fontFamily: fontFamily)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.updateData(lines: lines, fontSize: fontSize, fontFamily: fontFamily)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource {
        weak var tableView: NSTableView?
        var lines: [ChatDiffLine] = []
        var rowHeight: CGFloat = 18
        var fontSize: Double = 12
        var fontFamily: String = "Menlo"

        private var lastDataHash: Int = 0

        func updateData(lines: [ChatDiffLine], fontSize: Double, fontFamily: String) {
            let newHash = lines.count ^ fontSize.hashValue ^ fontFamily.hashValue
            guard newHash != lastDataHash else { return }

            lastDataHash = newHash
            self.lines = lines
            self.fontSize = fontSize
            self.fontFamily = fontFamily

            let font = NSFont(name: fontFamily, size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            rowHeight = ceil(font.ascender - font.descender + font.leading) + 4

            tableView?.reloadData()
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            lines.count
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            rowHeight
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < lines.count else { return nil }

            let id = NSUserInterfaceItemIdentifier("ChatDiffLine")
            let cell: ChatDiffLineCell
            if let existingCell = tableView.makeView(withIdentifier: id, owner: nil) as? ChatDiffLineCell {
                cell = existingCell
            } else {
                cell = ChatDiffLineCell(frame: .zero)
                cell.identifier = id
            }

            cell.configure(line: lines[row], fontSize: fontSize, fontFamily: fontFamily)
            return cell
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            guard row < lines.count else { return nil }
            let rowView = ChatDiffRowView()
            rowView.lineType = lines[row].type
            return rowView
        }

        func getSelectedContent() -> String {
            guard let tableView = tableView else { return "" }
            var result: [String] = []
            for rowIndex in tableView.selectedRowIndexes {
                guard rowIndex < lines.count else { continue }
                let line = lines[rowIndex]
                result.append("\(line.type.marker) \(line.content)")
            }
            return result.joined(separator: "\n")
        }
    }
}
