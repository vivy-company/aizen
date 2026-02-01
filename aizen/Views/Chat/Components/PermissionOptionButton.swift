//
//  PermissionOptionButton.swift
//  aizen
//
//  Shared permission action button styling
//

import ACP
import SwiftUI

struct PermissionOptionButton: View {
    enum Style {
        case banner
        case inline
    }

    let option: PermissionOption
    let style: Style
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: iconSpacing) {
                if let icon = iconName {
                    Image(systemName: icon)
                        .font(.system(size: iconSize))
                }
                Text(option.name)
                    .font(.system(size: fontSize, weight: .medium))
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var iconName: String? {
        if option.kind.contains("allow") {
            return "checkmark.circle.fill"
        }
        if option.kind.contains("reject") {
            return "xmark.circle.fill"
        }
        return nil
    }

    private var foregroundColor: Color {
        if option.kind.contains("allow") || option.kind.contains("reject") {
            return .white
        }
        return .primary
    }

    private var backgroundColor: Color {
        if option.kind == "allow_always" {
            return .green
        }
        if option.kind.contains("allow") {
            return .blue
        }
        if option.kind.contains("reject") {
            return .red
        }
        return .clear
    }

    private var fontSize: CGFloat {
        switch style {
        case .banner:
            return 11
        case .inline:
            return 11
        }
    }

    private var iconSize: CGFloat {
        switch style {
        case .banner:
            return 10
        case .inline:
            return 10
        }
    }

    private var horizontalPadding: CGFloat {
        switch style {
        case .banner:
            return 10
        case .inline:
            return 8
        }
    }

    private var verticalPadding: CGFloat {
        switch style {
        case .banner:
            return 6
        case .inline:
            return 4
        }
    }

    private var iconSpacing: CGFloat {
        switch style {
        case .banner:
            return 4
        case .inline:
            return 3
        }
    }
}
