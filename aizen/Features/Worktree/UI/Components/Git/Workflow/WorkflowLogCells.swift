//
//  WorkflowLogCells.swift
//  aizen
//
//  NSTableView cell views for workflow log display
//

import AppKit

// MARK: - Row View

class LogRowView: NSTableRowView {
    var isHeader: Bool = false
    var isStepHeader: Bool = false

    override func drawBackground(in dirtyRect: NSRect) {
        if isStepHeader {
            NSColor.controlBackgroundColor.setFill()
            dirtyRect.fill()
        } else if isHeader {
            NSColor.controlBackgroundColor.withAlphaComponent(0.3).setFill()
            dirtyRect.fill()
        }
    }

    override func drawSelection(in dirtyRect: NSRect) {
        NSColor.unemphasizedSelectedContentBackgroundColor.setFill()
        dirtyRect.fill()
    }
}

// MARK: - Step Header Cell

class StepHeaderCellView: NSView {
    private let chevronButton = NSButton()
    private let titleLabel = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")
    private let copyButton = NSButton()
    private var stepId: Int = 0
    private var onToggle: ((Int) -> Void)?
    private var onCopy: ((Int) -> Void)?
    private var resetWorkItem: DispatchWorkItem?

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        chevronButton.bezelStyle = .inline
        chevronButton.isBordered = false
        chevronButton.target = self
        chevronButton.action = #selector(toggleTapped)
        chevronButton.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        countLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        countLabel.textColor = .tertiaryLabelColor
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        copyButton.bezelStyle = .inline
        copyButton.isBordered = false
        copyButton.target = self
        copyButton.action = #selector(copyTapped)
        setCopyButtonDefault()
        copyButton.toolTip = "Copy step logs"
        copyButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(chevronButton)
        addSubview(titleLabel)
        addSubview(countLabel)
        addSubview(copyButton)

        NSLayoutConstraint.activate([
            chevronButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            chevronButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevronButton.widthAnchor.constraint(equalToConstant: 16),

            titleLabel.leadingAnchor.constraint(equalTo: chevronButton.trailingAnchor, constant: 4),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            countLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            countLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            copyButton.leadingAnchor.constraint(equalTo: countLabel.trailingAnchor, constant: 6),
            copyButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            copyButton.widthAnchor.constraint(equalToConstant: 16),
            copyButton.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    private func setCopyButtonDefault() {
        let image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy")?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .regular))
        copyButton.image = image
        copyButton.contentTintColor = .tertiaryLabelColor
    }

    private func setCopyButtonSuccess() {
        let image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Copied")?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .medium))
        copyButton.image = image
        copyButton.contentTintColor = .systemGreen
    }

    func configure(id: Int, name: String, count: Int, isExpanded: Bool, fontSize: CGFloat, onToggle: @escaping (Int) -> Void, onCopy: @escaping (Int) -> Void) {
        self.stepId = id
        self.onToggle = onToggle
        self.onCopy = onCopy

        chevronButton.image = NSImage(systemSymbolName: isExpanded ? "chevron.down" : "chevron.right", accessibilityDescription: nil)
        chevronButton.contentTintColor = .labelColor
        titleLabel.stringValue = name
        titleLabel.font = .systemFont(ofSize: fontSize + 1, weight: .semibold)
        countLabel.stringValue = "\(count) lines"
        countLabel.font = .monospacedSystemFont(ofSize: fontSize - 1, weight: .regular)
    }

    @objc private func toggleTapped() {
        onToggle?(stepId)
    }

    @objc private func copyTapped() {
        onCopy?(stepId)

        // Show success feedback
        resetWorkItem?.cancel()
        setCopyButtonSuccess()

        let workItem = DispatchWorkItem { [weak self] in
            self?.setCopyButtonDefault()
        }
        resetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: workItem)
    }
}

// MARK: - Group Header Cell

class GroupHeaderCellView: NSView {
    private let chevronButton = NSButton()
    private let titleLabel = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")
    private var groupId: Int = 0
    private var stepId: Int = 0
    private var onToggle: ((Int, Int) -> Void)?

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        chevronButton.bezelStyle = .inline
        chevronButton.isBordered = false
        chevronButton.target = self
        chevronButton.action = #selector(toggleTapped)
        chevronButton.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        countLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        countLabel.textColor = .tertiaryLabelColor
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(chevronButton)
        addSubview(titleLabel)
        addSubview(countLabel)

        NSLayoutConstraint.activate([
            chevronButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            chevronButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevronButton.widthAnchor.constraint(equalToConstant: 14),

            titleLabel.leadingAnchor.constraint(equalTo: chevronButton.trailingAnchor, constant: 4),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            countLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 6),
            countLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(id: Int, stepId: Int, title: String, count: Int, isExpanded: Bool, fontSize: CGFloat, onToggle: @escaping (Int, Int) -> Void) {
        self.groupId = id
        self.stepId = stepId
        self.onToggle = onToggle

        chevronButton.image = NSImage(systemSymbolName: isExpanded ? "chevron.down" : "chevron.right", accessibilityDescription: nil)
        chevronButton.contentTintColor = .tertiaryLabelColor
        titleLabel.stringValue = title
        titleLabel.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        countLabel.stringValue = "(\(count))"
        countLabel.font = .monospacedSystemFont(ofSize: fontSize - 1, weight: .regular)
    }

    @objc private func toggleTapped() {
        onToggle?(groupId, stepId)
    }
}

// MARK: - Log Line Cell

class LogLineCellView: NSView {
    private let label = NSTextField(wrappingLabelWithString: "")

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        label.isSelectable = true
        label.isEditable = false
        label.drawsBackground = false
        label.isBordered = false
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.allowsDefaultTighteningForTruncation = false
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            label.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -1),
        ])
    }

    override func layout() {
        super.layout()
        let availableWidth = bounds.width - 20
        if availableWidth > 0 {
            label.preferredMaxLayoutWidth = availableWidth
        }
    }

    func configure(attributed: NSAttributedString) {
        label.attributedStringValue = attributed
    }
}
