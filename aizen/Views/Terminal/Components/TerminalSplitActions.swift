//
//  TerminalSplitActions.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI

// MARK: - Terminal Split Actions (for keyboard shortcuts)

final class TerminalSplitActions {
    private var splitHorizontalHandler: (() -> Void)?
    private var splitVerticalHandler: (() -> Void)?
    private var closePaneHandler: (() -> Void)?

    func configure(
        splitHorizontal: @escaping () -> Void,
        splitVertical: @escaping () -> Void,
        closePane: @escaping () -> Void
    ) {
        splitHorizontalHandler = splitHorizontal
        splitVerticalHandler = splitVertical
        closePaneHandler = closePane
    }

    func clear() {
        splitHorizontalHandler = nil
        splitVerticalHandler = nil
        closePaneHandler = nil
    }

    func splitHorizontal() {
        splitHorizontalHandler?()
    }

    func splitVertical() {
        splitVerticalHandler?()
    }

    func closePane() {
        closePaneHandler?()
    }
}

private struct TerminalSplitActionsKey: FocusedValueKey {
    typealias Value = TerminalSplitActions
}

extension FocusedValues {
    var terminalSplitActions: TerminalSplitActions? {
        get { self[TerminalSplitActionsKey.self] }
        set { self[TerminalSplitActionsKey.self] = newValue }
    }
}
