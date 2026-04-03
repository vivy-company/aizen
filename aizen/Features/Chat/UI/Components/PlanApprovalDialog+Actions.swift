import ACP
import SwiftUI

extension PlanApprovalDialog {
    func buttonIcon(for option: PermissionOption) -> String {
        if option.kind == "allow_always" {
            return "checkmark.circle.fill"
        } else if option.kind.contains("allow") {
            return "checkmark"
        } else if option.kind.contains("reject") {
            return "xmark"
        }
        return "circle"
    }

    func buttonForeground(for option: PermissionOption) -> Color {
        if option.kind.contains("allow") || option.kind.contains("reject") {
            return .white
        }
        return .primary
    }

    func buttonBackground(for option: PermissionOption) -> Color {
        if option.kind == "allow_always" {
            return .green
        } else if option.kind.contains("allow") {
            return .blue
        } else if option.kind.contains("reject") {
            return .red.opacity(0.85)
        }
        return .secondary.opacity(0.2)
    }
}
