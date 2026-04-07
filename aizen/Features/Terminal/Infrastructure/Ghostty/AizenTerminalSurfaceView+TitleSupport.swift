import AppKit

extension Ghostty.SurfaceView {
    /// Set the title by prompting the user.
    func promptTitle() {
        let alert = NSAlert()
        alert.messageText = "Change Terminal Title"
        alert.informativeText = "Leave blank to restore the default."
        alert.alertStyle = .informational

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
        textField.stringValue = title
        alert.accessoryView = textField

        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = textField

        let completionHandler: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            guard response == .alertFirstButtonReturn else { return }

            let newTitle = textField.stringValue
            if newTitle.isEmpty {
                let prevTitle = titleFromTerminal ?? "👻"
                titleFromTerminal = nil
                setTitle(prevTitle)
            } else {
                titleFromTerminal = title
                title = newTitle
            }
        }

        if let window {
            alert.beginSheetModal(for: window, completionHandler: completionHandler)
        } else {
            completionHandler(alert.runModal())
        }
    }

    func setTitle(_ title: String) {
        titleChangeTimer?.invalidate()
        titleChangeTimer = Timer.scheduledTimer(
            withTimeInterval: 0.075,
            repeats: false
        ) { [weak self] _ in
            guard self?.titleFromTerminal == nil else {
                self?.titleFromTerminal = title
                return
            }
            self?.title = title
        }
    }
}
