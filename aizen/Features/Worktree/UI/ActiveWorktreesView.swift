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
    @StateObject var workspaceGraphQueryController: WorkspaceGraphQueryController

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

    init(context: NSManagedObjectContext) {
        _workspaceGraphQueryController = StateObject(
            wrappedValue: WorkspaceGraphQueryController(viewContext: context)
        )
    }
}
