//
//  AgentSwitcher.swift
//  aizen
//
//  Handles agent switching logic and Core Data persistence
//

import CoreData
import Foundation
import os.log

@MainActor
class AgentSwitcher {
    private let viewContext: NSManagedObjectContext
    private let session: ChatSession
    private let logger = Logger.forCategory("AgentSwitcher")

    init(viewContext: NSManagedObjectContext, session: ChatSession) {
        self.viewContext = viewContext
        self.session = session
    }

    func performAgentSwitch(to newAgent: String) {
        session.agentName = newAgent
        let displayName = AgentRegistry.shared.getMetadata(for: newAgent)?.name ?? newAgent.capitalized
        session.title = displayName

        do {
            try viewContext.save()
        } catch {
            logger.error("Failed to save agent switch: \(error.localizedDescription)")
        }
    }
}
