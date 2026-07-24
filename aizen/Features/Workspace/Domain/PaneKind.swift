//
//  PaneKind.swift
//  aizen
//
//  Content type hosted by a workspace pane.
//

import Foundation

nonisolated enum PaneKind: String, Codable, CaseIterable, Hashable {
    case terminal
    case chat
    case files
    case browser
    case gitDiff
    case empty
}
