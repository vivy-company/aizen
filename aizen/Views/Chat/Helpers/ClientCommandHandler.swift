//
//  ClientCommandHandler.swift
//  aizen
//
//  Centralized handler for client-side slash commands
//

import Foundation
import SwiftUI
import CoreData

@MainActor
struct ClientCommand {
    let name: String
    let aliases: [String]
    let description: String
    let execute: (NSManagedObjectContext) -> Void
}

@MainActor
final class ClientCommandHandler {
    static let shared = ClientCommandHandler()
    
    private init() {}
    
    private lazy var commands: [ClientCommand] = [
        ClientCommand(
            name: "sessions",
            aliases: ["session"],
            description: "View and manage chat session history",
            execute: { context in
                SessionsWindowManager.shared.show(context: context)
            }
        )
    ]
    
    var availableCommands: [AvailableCommand] {
        commands.map { cmd in
            AvailableCommand(
                name: cmd.name,
                description: cmd.description,
                input: nil,
                _meta: nil
            )
        }
    }
    
    func handle(_ input: String, context: NSManagedObjectContext) -> Bool {
        guard input.hasPrefix("/") else { return false }
        
        let commandText = String(input.dropFirst()).lowercased().trimmingCharacters(in: .whitespaces)
        
        guard let command = commands.first(where: {
            $0.name.lowercased() == commandText || $0.aliases.contains(where: { $0.lowercased() == commandText })
        }) else {
            return false
        }
        
        command.execute(context)
        return true
    }
}
