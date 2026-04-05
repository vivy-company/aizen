//
//  WorkflowLogCells.swift
//  aizen
//
//  NSTableView cell views for workflow log display
//

import AppKit

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
