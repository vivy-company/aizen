//
//  TerminalSplitController+LayoutActions.swift
//  aizen
//
//  Split tree mutation and pane creation actions.
//

import SwiftUI

@MainActor
extension TerminalSplitController {
    func resizeSplit(_ node: SplitNode, to newRatio: CGFloat) {
        let updatedSplit = node.withUpdatedRatio(Double(newRatio))
        layout = layout.replacingNode(node, with: updatedSplit)
    }

    func equalize() {
        layout = layout.equalized()
    }

    func splitHorizontal() {
        splitRight()
    }

    func splitVertical() {
        splitDown()
    }

    func splitRight() {
        let sourcePaneId = activePaneId()
        let newPaneId = UUID().uuidString
        let newSplit = SplitNode.split(SplitNode.Split(
            direction: .horizontal,
            ratio: 0.5,
            left: .leaf(paneId: sourcePaneId),
            right: .leaf(paneId: newPaneId)
        ))
        layout = layout.replacingPane(sourcePaneId, with: newSplit)
        focusedPaneId = newPaneId
        focusRequestVersion += 1
        activateSplitActions()
    }

    func splitLeft() {
        let sourcePaneId = activePaneId()
        let newPaneId = UUID().uuidString
        let newSplit = SplitNode.split(SplitNode.Split(
            direction: .horizontal,
            ratio: 0.5,
            left: .leaf(paneId: newPaneId),
            right: .leaf(paneId: sourcePaneId)
        ))
        layout = layout.replacingPane(sourcePaneId, with: newSplit)
        focusedPaneId = newPaneId
        focusRequestVersion += 1
        activateSplitActions()
    }

    func splitDown() {
        let sourcePaneId = activePaneId()
        let newPaneId = UUID().uuidString
        let newSplit = SplitNode.split(SplitNode.Split(
            direction: .vertical,
            ratio: 0.5,
            left: .leaf(paneId: sourcePaneId),
            right: .leaf(paneId: newPaneId)
        ))
        layout = layout.replacingPane(sourcePaneId, with: newSplit)
        focusedPaneId = newPaneId
        focusRequestVersion += 1
        activateSplitActions()
    }

    func splitUp() {
        let sourcePaneId = activePaneId()
        let newPaneId = UUID().uuidString
        let newSplit = SplitNode.split(SplitNode.Split(
            direction: .vertical,
            ratio: 0.5,
            left: .leaf(paneId: newPaneId),
            right: .leaf(paneId: sourcePaneId)
        ))
        layout = layout.replacingPane(sourcePaneId, with: newSplit)
        focusedPaneId = newPaneId
        focusRequestVersion += 1
        activateSplitActions()
    }
}
