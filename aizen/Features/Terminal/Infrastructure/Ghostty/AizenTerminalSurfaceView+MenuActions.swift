import AppKit
import CoreText
import GhosttyKit
import OSLog

extension Ghostty.SurfaceView {
    override func quickLook(with event: NSEvent) {
        guard let surface = self.surface else { return super.quickLook(with: event) }

        var text = ghostty_text_s()
        guard ghostty_surface_quicklook_word(surface, &text) else { return super.quickLook(with: event) }
        defer { ghostty_surface_free_text(surface, &text) }
        guard text.text_len > 0 else { return super.quickLook(with: event) }

        var attributes: [NSAttributedString.Key: Any] = [:]
        if let fontRaw = ghostty_surface_quicklook_font(surface) {
            let font = Unmanaged<CTFont>.fromOpaque(fontRaw)
            attributes[.font] = font.takeUnretainedValue()
            font.release()
        }

        let pt = NSPoint(x: text.tl_px_x, y: frame.size.height - text.tl_px_y)
        let str = NSAttributedString(string: String(cString: text.text), attributes: attributes)
        self.showDefinition(for: str, at: pt)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        switch event.type {
        case .rightMouseDown:
            break
        case .leftMouseDown:
            if !event.modifierFlags.contains(.control) {
                return nil
            }

            guard let surfaceModel else { return nil }
            if surfaceModel.mouseCaptured {
                return nil
            }

            _ = surfaceModel.sendMouseButton(.init(
                action: .press,
                button: .right,
                mods: .init(nsFlags: event.modifierFlags)
            ))
        default:
            return nil
        }

        let menu = NSMenu()
        menu.autoenablesItems = false

        var item: NSMenuItem

        if let text = self.accessibilitySelectedText(), text.count > 0 {
            item = menu.addItem(withTitle: "Copy", action: #selector(copy(_:)), keyEquivalent: "")
            item.target = self
        }
        item = menu.addItem(withTitle: "Paste", action: #selector(paste(_:)), keyEquivalent: "")
        item.target = self

        menu.addItem(.separator())
        item = menu.addItem(withTitle: "Split Right", action: #selector(splitRight(_:)), keyEquivalent: "")
        item.target = self
        item.setImageIfDesired(systemSymbolName: "rectangle.righthalf.inset.filled")
        item = menu.addItem(withTitle: "Split Left", action: #selector(splitLeft(_:)), keyEquivalent: "")
        item.target = self
        item.setImageIfDesired(systemSymbolName: "rectangle.leadinghalf.inset.filled")
        item = menu.addItem(withTitle: "Split Down", action: #selector(splitDown(_:)), keyEquivalent: "")
        item.target = self
        item.setImageIfDesired(systemSymbolName: "rectangle.bottomhalf.inset.filled")
        item = menu.addItem(withTitle: "Split Up", action: #selector(splitUp(_:)), keyEquivalent: "")
        item.target = self
        item.setImageIfDesired(systemSymbolName: "rectangle.tophalf.inset.filled")

        menu.addItem(.separator())
        item = menu.addItem(withTitle: "Reset Terminal", action: #selector(resetTerminal(_:)), keyEquivalent: "")
        item.target = self
        item.setImageIfDesired(systemSymbolName: "arrow.trianglehead.2.clockwise")
        item = menu.addItem(withTitle: "Terminal Read-only", action: #selector(toggleReadonly(_:)), keyEquivalent: "")
        item.target = self
        item.setImageIfDesired(systemSymbolName: "eye.fill")
        item.state = readonly ? .on : .off
        menu.addItem(.separator())
        item = menu.addItem(withTitle: "Change Terminal Title...", action: #selector(changeTitle(_:)), keyEquivalent: "")
        item.target = self

        return menu
    }

    @IBAction func copy(_ sender: Any?) {
        guard let surface = self.surface else { return }
        let action = "copy_to_clipboard"
        if !ghostty_surface_binding_action(surface, action, UInt(action.lengthOfBytes(using: .utf8))) {
            Self.logger.warning("action failed action=\(action)")
        }
    }

    @IBAction func paste(_ sender: Any?) {
        focusMenuPane()
        guard let surface = self.surface else { return }
        let action = "paste_from_clipboard"
        if !ghostty_surface_binding_action(surface, action, UInt(action.lengthOfBytes(using: .utf8))) {
            Self.logger.warning("action failed action=\(action)")
        }
    }

    @IBAction func pasteAsPlainText(_ sender: Any?) {
        focusMenuPane()
        guard let surface = self.surface else { return }
        let action = "paste_from_clipboard"
        if !ghostty_surface_binding_action(surface, action, UInt(action.lengthOfBytes(using: .utf8))) {
            Self.logger.warning("action failed action=\(action)")
        }
    }

    @IBAction func pasteSelection(_ sender: Any?) {
        focusMenuPane()
        guard let surface = self.surface else { return }
        let action = "paste_from_selection"
        if !ghostty_surface_binding_action(surface, action, UInt(action.lengthOfBytes(using: .utf8))) {
            Self.logger.warning("action failed action=\(action)")
        }
    }

    @IBAction override func selectAll(_ sender: Any?) {
        guard let surface = self.surface else { return }
        let action = "select_all"
        if !ghostty_surface_binding_action(surface, action, UInt(action.lengthOfBytes(using: .utf8))) {
            Self.logger.warning("action failed action=\(action)")
        }
    }

    @IBAction func find(_ sender: Any?) {
        guard let surface = self.surface else { return }
        let action = "start_search"
        if !ghostty_surface_binding_action(surface, action, UInt(action.lengthOfBytes(using: .utf8))) {
            Self.logger.warning("action failed action=\(action)")
        }
    }

    @IBAction func selectionForFind(_ sender: Any?) {
        guard let surface = self.surface else { return }
        let action = "search_selection"
        if !ghostty_surface_binding_action(surface, action, UInt(action.lengthOfBytes(using: .utf8))) {
            Self.logger.warning("action failed action=\(action)")
        }
    }

    @IBAction func scrollToSelection(_ sender: Any?) {
        guard let surface = self.surface else { return }
        let action = "scroll_to_selection"
        if !ghostty_surface_binding_action(surface, action, UInt(action.lengthOfBytes(using: .utf8))) {
            Self.logger.warning("action failed action=\(action)")
        }
    }

    @IBAction func findNext(_ sender: Any?) {
        guard let surface = self.surface else { return }
        let action = "search:next"
        if !ghostty_surface_binding_action(surface, action, UInt(action.lengthOfBytes(using: .utf8))) {
            Self.logger.warning("action failed action=\(action)")
        }
    }

    @IBAction func findPrevious(_ sender: Any?) {
        guard let surface = self.surface else { return }
        let action = "search:previous"
        if !ghostty_surface_binding_action(surface, action, UInt(action.lengthOfBytes(using: .utf8))) {
            Self.logger.warning("action failed action=\(action)")
        }
    }

    @IBAction func findHide(_ sender: Any?) {
        guard let surface = self.surface else { return }
        let action = "end_search"
        if !ghostty_surface_binding_action(surface, action, UInt(action.lengthOfBytes(using: .utf8))) {
            Self.logger.warning("action failed action=\(action)")
        }
    }

    @IBAction func toggleReadonly(_ sender: Any?) {
        guard let surface = self.surface else { return }
        let action = "toggle_readonly"
        if !ghostty_surface_binding_action(surface, action, UInt(action.lengthOfBytes(using: .utf8))) {
            Self.logger.warning("action failed action=\(action)")
        }
    }

    func highlight() {
        highlighted = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.highlighted = false
        }
    }

    private func focusMenuPane() {
        if !isCurrentFirstResponder {
            Ghostty.moveFocus(to: self)
        }
        (self as? AizenTerminalSurfaceView)?.onFocus?()
    }

    @IBAction func splitRight(_ sender: Any) {
        focusMenuPane()
        TerminalSplitActionRouter.shared.splitRight()
    }

    @IBAction func splitLeft(_ sender: Any) {
        focusMenuPane()
        TerminalSplitActionRouter.shared.splitLeft()
    }

    @IBAction func splitDown(_ sender: Any) {
        focusMenuPane()
        TerminalSplitActionRouter.shared.splitDown()
    }

    @IBAction func splitUp(_ sender: Any) {
        focusMenuPane()
        TerminalSplitActionRouter.shared.splitUp()
    }

    @objc func resetTerminal(_ sender: Any) {
        guard let surface = self.surface else { return }
        let action = "reset"
        if !ghostty_surface_binding_action(surface, action, UInt(action.lengthOfBytes(using: .utf8))) {
            Self.logger.warning("action failed action=\(action)")
        }
    }

    @IBAction func changeTitle(_ sender: Any) {
        promptTitle()
    }
}
