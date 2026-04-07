import ACP
import SwiftUI

extension PlanApprovalPickerView {
    var canSubmit: Bool {
        !options.isEmpty && selectedIndex >= 0 && selectedIndex < options.count
    }

    func submitSelectedOption() {
        guard canSubmit else { return }
        let option = options[selectedIndex]
        session.respondToPermission(optionId: option.optionId)
    }

    func submitOption(at index: Int) {
        guard index >= 0 && index < options.count else { return }
        selectedIndex = index
        session.respondToPermission(optionId: options[index].optionId)
    }

    func dismissRequest() {
        if let option = preferredDismissOption {
            session.respondToPermission(optionId: option.optionId)
        } else {
            session.permissionHandler.cancelPendingRequest()
            onDismissWithoutResponse()
        }
    }

    var preferredDismissOption: PermissionOption? {
        options.first(where: { isDismissOption($0.kind) }) ?? options.last
    }

    func isDismissOption(_ kind: String) -> Bool {
        let normalized = kind.lowercased()
        return normalized.contains("reject")
            || normalized.contains("deny")
            || normalized.contains("cancel")
            || normalized.contains("decline")
    }

    func moveSelection(_ delta: Int) {
        guard options.count > 1 else { return }
        let next = max(0, min(selectedIndex + delta, options.count - 1))
        selectedIndex = next
    }

    func numberShortcut(for index: Int) -> KeyEquivalent {
        let number = min(max(index + 1, 1), 9)
        return KeyEquivalent(Character("\(number)"))
    }
}
