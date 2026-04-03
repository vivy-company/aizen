import AppKit

extension PlanApprovalPickerView {
    func installKeyboardMonitorIfNeeded() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if handleKeyDown(event) {
                return nil
            }
            return event
        }
    }

    func removeKeyboardMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 126: // Up arrow
            moveSelection(-1)
            return true
        case 125: // Down arrow
            moveSelection(1)
            return true
        case 36, 76: // Return / Enter
            submitSelectedOption()
            return true
        case 53: // Escape
            dismissRequest()
            return true
        default:
            if let index = numberKeyCodeToIndex[event.keyCode], index < options.count {
                submitOption(at: index)
                return true
            }
            break
        }

        return false
    }

    var numberKeyCodeToIndex: [UInt16: Int] {
        // Top-row number key codes on macOS keyboard layout: 1...9
        [18: 0, 19: 1, 20: 2, 21: 3, 23: 4, 22: 5, 26: 6, 28: 7, 25: 8]
    }
}
