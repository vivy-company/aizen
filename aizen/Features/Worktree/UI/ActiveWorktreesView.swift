//
//  ActiveWorktreesView.swift
//  aizen
//
//  Activity Monitor for active environments.
//

import CoreData
import SwiftUI
import os.log

@MainActor
struct ActiveWorktreesView: View {
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.colorScheme) var colorScheme
    @StateObject var metrics = ActiveWorktreesMetrics()

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Worktree.lastAccessed, ascending: false)],
        animation: .default
    )
    var worktrees: FetchedResults<Worktree>

    @AppStorage("terminalSessionPersistence") var sessionPersistence = false

    @State var searchText = ""
    @State var selectedMode: ActiveWorktreesMonitorMode = .chats
    @State var selectedScope: ActiveWorktreesScopeSelection = .all
    @State var selectedRowID: ActiveWorktreesMonitorRow.ID?
    @State var showTerminateAllConfirm = false
    @State var sortOrder: [KeyPathComparator<ActiveWorktreesMonitorRow>] = [
        KeyPathComparator(\.chatSessions, order: .reverse),
        KeyPathComparator(\.lastAccessed, order: .reverse)
    ]

    func rowMatchesSelectedMode(_ row: ActiveWorktreesMonitorRow) -> Bool {
        switch selectedMode {
        case .chats:
            return row.chatSessions > 0
        case .terminals:
            return row.terminalSessions > 0
        case .files:
            return row.fileSessions > 0
        case .browsers:
            return row.browserSessions > 0
        }
    }

}
