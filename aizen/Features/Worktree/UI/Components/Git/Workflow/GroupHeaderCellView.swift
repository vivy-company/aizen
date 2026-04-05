//
//  GroupHeaderCellView.swift
//  aizen
//
//  Created by OpenAI Codex on 06.04.26.
//

import AppKit

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
