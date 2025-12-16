//
//  TabItem.swift
//  aizen
//

import Foundation

struct TabItem: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let localizedKey: String
    let icon: String

    static let chat = TabItem(id: "chat", localizedKey: "worktree.session.chat", icon: "message")
    static let terminal = TabItem(id: "terminal", localizedKey: "worktree.session.terminal", icon: "terminal")
    static let files = TabItem(id: "files", localizedKey: "worktree.session.files", icon: "folder")
    static let browser = TabItem(id: "browser", localizedKey: "worktree.session.browser", icon: "globe")

    static let defaultOrder: [TabItem] = [.chat, .terminal, .files, .browser]

    static func from(id: String) -> TabItem? {
        defaultOrder.first { $0.id == id }
    }
}
