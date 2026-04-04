//
//  BranchTemplate.swift
//  aizen
//

import Foundation

struct BranchTemplate: Codable, Identifiable, Equatable {
    let id: UUID
    var prefix: String
    var icon: String

    init(
        id: UUID = UUID(),
        prefix: String,
        icon: String = "arrow.triangle.branch"
    ) {
        self.id = id
        self.prefix = prefix
        self.icon = icon
    }
}
