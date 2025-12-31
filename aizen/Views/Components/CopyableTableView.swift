//
//  CopyableTableView.swift
//  aizen
//
//  NSTableView with shared copy-to-clipboard handling
//

import AppKit

protocol CopyableTableViewProvider: AnyObject {
    func selectedCopyText() -> String
}

class CopyableTableView: NSTableView {
    weak var copyProvider: CopyableTableViewProvider?

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "c" {
            copy(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    @objc func copy(_ sender: Any?) {
        guard let text = copyProvider?.selectedCopyText(), !text.isEmpty else { return }
        Clipboard.copy(text)
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(copy(_:)) {
            return selectedRowIndexes.count > 0
        }
        return super.validateUserInterfaceItem(item)
    }
}
