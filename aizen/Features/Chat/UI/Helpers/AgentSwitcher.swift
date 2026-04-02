//
//  AgentSwitcher.swift
//  aizen
//
//  Handles agent switching logic and Core Data persistence
//

import CoreData
import Foundation
import os.log
import Combine

@MainActor
class AgentSwitcher {
    private let viewContext: NSManagedObjectContext
    private let session: ChatSession
    private let logger = Logger.forCategory("AgentSwitcher")

    init(viewContext: NSManagedObjectContext, session: ChatSession) {
        self.viewContext = viewContext
        self.session = session
    }

    func performAgentSwitch(to newAgent: String, worktree: Worktree, objectWillChange: @escaping () -> Void) {
        session.agentName = newAgent
        let displayName = AgentRegistry.shared.getMetadata(for: newAgent)?.name ?? newAgent.capitalized
        session.title = displayName

        session.objectWillChange.send()
        worktree.objectWillChange.send()

        objectWillChange()

        do {
            try viewContext.save()
        } catch {
            logger.error("Failed to save agent switch: \(error.localizedDescription)")
        }
    }
}
