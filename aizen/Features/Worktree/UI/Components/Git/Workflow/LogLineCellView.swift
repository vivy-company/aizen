//
//  LogLineCellView.swift
//  aizen
//
//  Created by OpenAI Codex on 06.04.26.
//

import AppKit

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
