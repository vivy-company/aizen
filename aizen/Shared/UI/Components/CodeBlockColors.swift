//
//  CodeBlockColors.swift
//  aizen
//
//  Shared color tokens for code/diagram blocks
//

import SwiftUI

enum CodeBlockColors {
    static func headerBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.15) : Color(white: 0.95)
    }

    static func contentBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.1) : Color(white: 0.98)
    }
}
