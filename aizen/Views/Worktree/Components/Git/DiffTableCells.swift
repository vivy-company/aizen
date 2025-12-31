//
//  DiffTableCells.swift
//  aizen
//
//  Cell views for diff table rendering
//

import AppKit
import UniformTypeIdentifiers

// MARK: - Row View

class DiffNSRowView: NSTableRowView {
    var lineType: DiffLineType? {
        didSet { needsDisplay = true }
    }

    override func drawBackground(in dirtyRect: NSRect) {
        guard let type = lineType else {
            // File header
            NSColor.controlBackgroundColor.withAlphaComponent(0.8).setFill()
            bounds.fill()
            return
        }
        type.nsBackgroundColor.setFill()
        bounds.fill()
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        // Use accent color with appropriate opacity for visibility
        NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
        bounds.fill()
        // Left border indicator
        NSColor.controlAccentColor.setFill()
        NSRect(x: 0, y: 0, width: 3, height: bounds.height).fill()
    }

    // Prevent automatic text color inversion when selected
    override var interiorBackgroundStyle: NSView.BackgroundStyle {
        .normal
    }
}

// MARK: - File Header Cell

class FileHeaderCellView: NSTableCellView {
    private let iconView = NSImageView()
    private let pathLabel = NSTextField(labelWithString: "")
    private let openButton = NSButton()
    private var currentPath: String = ""
    private var onOpenFile: ((String) -> Void)?

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        setupViews()
    }

    required init?(coder: NSCoder) { nil }

    private func setupViews() {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown

        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.maximumNumberOfLines = 1

        openButton.translatesAutoresizingMaskIntoConstraints = false
        openButton.bezelStyle = .accessoryBarAction
        openButton.isBordered = false
        openButton.image = NSImage(systemSymbolName: "arrow.up.forward.square", accessibilityDescription: "Open in editor")
        openButton.contentTintColor = .secondaryLabelColor
        openButton.target = self
        openButton.action = #selector(openFile)
        openButton.toolTip = "Open in editor"

        addSubview(iconView)
        addSubview(pathLabel)
        addSubview(openButton)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            iconView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            pathLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            pathLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),

            openButton.leadingAnchor.constraint(greaterThanOrEqualTo: pathLabel.trailingAnchor, constant: 8),
            openButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            openButton.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            openButton.widthAnchor.constraint(equalToConstant: 20),
            openButton.heightAnchor.constraint(equalToConstant: 20)
        ])
    }

    @objc private func openFile() {
        onOpenFile?(currentPath)
    }

    func configure(path: String, repoPath: String, fontSize: Double, fontFamily: String, onOpenFile: ((String) -> Void)?) {
        currentPath = path
        self.onOpenFile = onOpenFile

        pathLabel.stringValue = path
        pathLabel.font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)

        let fullPath = (repoPath as NSString).appendingPathComponent(path)
        Task { @MainActor in
            if let icon = await FileIconService.shared.icon(forFile: fullPath, size: CGSize(width: 16, height: 16)) {
                self.iconView.image = icon
            } else {
                let fileExtension = (path as NSString).pathExtension
                let contentType = UTType(filenameExtension: fileExtension) ?? .data
                self.iconView.image = NSWorkspace.shared.icon(for: contentType)
            }
        }
    }
}

// MARK: - Line Cell

class LineCellView: NSTableCellView {
    private let oldNumLabel = NSTextField(labelWithString: "")
    private let newNumLabel = NSTextField(labelWithString: "")
    private let markerLabel = NSTextField(labelWithString: "")
    private let contentLabel = NSTextField(labelWithString: "")
    private let lineNumBg = NSView()
    private let commentButton = NSButton()

    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var hasComment = false
    var onCommentTap: (() -> Void)?

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        setupViews()
    }

    required init?(coder: NSCoder) { nil }

    private func setupViews() {
        lineNumBg.wantsLayer = true
        updateGutterBackground()
        lineNumBg.translatesAutoresizingMaskIntoConstraints = false

        [oldNumLabel, newNumLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.alignment = .right
            $0.textColor = .tertiaryLabelColor
        }

        markerLabel.translatesAutoresizingMaskIntoConstraints = false
        markerLabel.alignment = .center

        contentLabel.translatesAutoresizingMaskIntoConstraints = false
        contentLabel.lineBreakMode = .byWordWrapping
        contentLabel.maximumNumberOfLines = 0
        contentLabel.isSelectable = true
        contentLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        contentLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // Comment button setup
        commentButton.translatesAutoresizingMaskIntoConstraints = false
        commentButton.bezelStyle = .accessoryBarAction
        commentButton.isBordered = false
        commentButton.target = self
        commentButton.action = #selector(commentButtonTapped)
        commentButton.isHidden = true

        addSubview(lineNumBg)
        addSubview(oldNumLabel)
        addSubview(newNumLabel)
        addSubview(commentButton)
        addSubview(markerLabel)
        addSubview(contentLabel)

        NSLayoutConstraint.activate([
            lineNumBg.leadingAnchor.constraint(equalTo: leadingAnchor),
            lineNumBg.topAnchor.constraint(equalTo: topAnchor),
            lineNumBg.bottomAnchor.constraint(equalTo: bottomAnchor),
            lineNumBg.widthAnchor.constraint(equalToConstant: 56),

            commentButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            commentButton.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            commentButton.widthAnchor.constraint(equalToConstant: 14),
            commentButton.heightAnchor.constraint(equalToConstant: 14),

            oldNumLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            oldNumLabel.widthAnchor.constraint(equalToConstant: 18),
            oldNumLabel.topAnchor.constraint(equalTo: topAnchor, constant: 3),

            newNumLabel.leadingAnchor.constraint(equalTo: oldNumLabel.trailingAnchor, constant: 2),
            newNumLabel.widthAnchor.constraint(equalToConstant: 18),
            newNumLabel.topAnchor.constraint(equalTo: topAnchor, constant: 3),

            markerLabel.leadingAnchor.constraint(equalTo: lineNumBg.trailingAnchor, constant: 4),
            markerLabel.widthAnchor.constraint(equalToConstant: 16),
            markerLabel.topAnchor.constraint(equalTo: topAnchor, constant: 3),

            contentLabel.leadingAnchor.constraint(equalTo: markerLabel.trailingAnchor, constant: 4),
            contentLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            contentLabel.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            contentLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3)
        ])
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = trackingArea {
            removeTrackingArea(area)
        }
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .activeInKeyWindow,
            .inVisibleRect
        ]
        trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)

        // Check if mouse is currently inside after tracking area update
        if let window = window {
            let mouseLocation = window.mouseLocationOutsideOfEventStream
            let localPoint = convert(mouseLocation, from: nil)
            let wasHovered = isHovered
            isHovered = bounds.contains(localPoint)
            if wasHovered != isHovered {
                updateCommentButtonVisibility()
            }
        }
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateCommentButtonVisibility()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateCommentButtonVisibility()
    }

    private func updateCommentButtonVisibility() {
        commentButton.isHidden = !isHovered && !hasComment
    }

    @objc private func commentButtonTapped() {
        onCommentTap?()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        isHovered = false
        hasComment = false
        onCommentTap = nil
        commentButton.isHidden = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Reset hover state when cell moves to window (reuse)
        isHovered = false
        if !hasComment {
            commentButton.isHidden = true
        }
        updateGutterBackground()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateGutterBackground()
    }

    private func updateGutterBackground() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let bgColor = isDark
            ? NSColor.white.withAlphaComponent(0.04)
            : NSColor.black.withAlphaComponent(0.03)
        lineNumBg.layer?.backgroundColor = bgColor.cgColor
    }

    func configure(
        diffLine: DiffLine,
        fontSize: Double,
        fontFamily: String,
        hasComment: Bool,
        onCommentTap: (() -> Void)?
    ) {
        // Reset hover state on reuse
        self.isHovered = false
        self.hasComment = hasComment
        self.onCommentTap = onCommentTap

        let font = NSFont(name: fontFamily, size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let smallFont = NSFont(name: fontFamily, size: fontSize - 1) ?? NSFont.monospacedSystemFont(ofSize: fontSize - 1, weight: .regular)

        oldNumLabel.stringValue = diffLine.oldLineNumber ?? ""
        oldNumLabel.font = smallFont
        oldNumLabel.alphaValue = diffLine.oldLineNumber != nil ? 1 : 0

        newNumLabel.stringValue = diffLine.newLineNumber ?? ""
        newNumLabel.font = smallFont
        newNumLabel.alphaValue = diffLine.newLineNumber != nil ? 1 : 0

        markerLabel.stringValue = diffLine.type.marker
        markerLabel.font = font
        markerLabel.textColor = diffLine.type.nsMarkerColor

        contentLabel.stringValue = diffLine.content.isEmpty ? " " : diffLine.content
        contentLabel.font = font

        // Update comment button appearance
        if hasComment {
            commentButton.image = NSImage(systemSymbolName: "text.bubble.fill", accessibilityDescription: "Edit comment")
            commentButton.contentTintColor = .systemBlue
            commentButton.isHidden = false
        } else {
            commentButton.image = NSImage(systemSymbolName: "bubble.left", accessibilityDescription: "Add comment")
            commentButton.contentTintColor = .tertiaryLabelColor
            commentButton.isHidden = true  // Only show on hover
        }
    }
}
