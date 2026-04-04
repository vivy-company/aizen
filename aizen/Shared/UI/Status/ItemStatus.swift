//
//  ItemStatus.swift
//  aizen
//

import SwiftUI

enum ItemStatus: String, CaseIterable, Identifiable {
    case active = "active"
    case paused = "paused"
    case archived = "archived"
    case maintenance = "maintenance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active: return String(localized: "status.active")
        case .paused: return String(localized: "status.paused")
        case .archived: return String(localized: "status.archived")
        case .maintenance: return String(localized: "status.maintenance")
        }
    }

    var color: Color {
        switch self {
        case .active: return .green
        case .paused: return .yellow
        case .archived: return .gray
        case .maintenance: return .orange
        }
    }

    var systemImage: String {
        switch self {
        case .active: return "checkmark.circle.fill"
        case .paused: return "pause.circle.fill"
        case .archived: return "archivebox.fill"
        case .maintenance: return "wrench.fill"
        }
    }

    // MARK: - Persistence Helpers

    /// Encode a set of filters to a string for UserDefaults storage
    static func encode(_ filters: Set<ItemStatus>) -> String {
        filters.map(\.rawValue).sorted().joined(separator: ",")
    }

    /// Decode a string from UserDefaults to a set of filters
    /// Returns all cases if the string is empty (default: show all)
    static func decode(_ string: String) -> Set<ItemStatus> {
        guard !string.isEmpty else { return Set(allCases) }
        let values = string.split(separator: ",").compactMap { ItemStatus(rawValue: String($0)) }
        return values.isEmpty ? Set(allCases) : Set(values)
    }
}
