//
//  TerminalSplitActionRouter.swift
//  aizen
//

final class TerminalSplitActionRouter {
    static let shared = TerminalSplitActionRouter()

    private weak var activeActions: TerminalSplitActions?

    private init() {}

    func activate(_ actions: TerminalSplitActions) {
        activeActions = actions
    }

    func clear(_ actions: TerminalSplitActions) {
        guard activeActions === actions else { return }
        activeActions = nil
    }

    func splitHorizontal() {
        activeActions?.splitHorizontal()
    }

    func splitVertical() {
        activeActions?.splitVertical()
    }

    func splitRight() {
        activeActions?.splitRight()
    }

    func splitLeft() {
        activeActions?.splitLeft()
    }

    func splitDown() {
        activeActions?.splitDown()
    }

    func splitUp() {
        activeActions?.splitUp()
    }

    func closePane() {
        activeActions?.closePane()
    }
}
