//
//  TerminalSplitActions.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

// MARK: - Terminal Split Actions (for keyboard shortcuts)

final class TerminalSplitActions {
    private var splitRightHandler: (() -> Void)?
    private var splitLeftHandler: (() -> Void)?
    private var splitDownHandler: (() -> Void)?
    private var splitUpHandler: (() -> Void)?
    private var closePaneHandler: (() -> Void)?

    func configure(
        splitRight: @escaping () -> Void,
        splitLeft: @escaping () -> Void,
        splitDown: @escaping () -> Void,
        splitUp: @escaping () -> Void,
        closePane: @escaping () -> Void
    ) {
        splitRightHandler = splitRight
        splitLeftHandler = splitLeft
        splitDownHandler = splitDown
        splitUpHandler = splitUp
        closePaneHandler = closePane
    }

    func clear() {
        splitRightHandler = nil
        splitLeftHandler = nil
        splitDownHandler = nil
        splitUpHandler = nil
        closePaneHandler = nil
    }

    func splitHorizontal() {
        splitRightHandler?()
    }

    func splitVertical() {
        splitDownHandler?()
    }

    func splitRight() {
        splitRightHandler?()
    }

    func splitLeft() {
        splitLeftHandler?()
    }

    func splitDown() {
        splitDownHandler?()
    }

    func splitUp() {
        splitUpHandler?()
    }

    func closePane() {
        closePaneHandler?()
    }
}
