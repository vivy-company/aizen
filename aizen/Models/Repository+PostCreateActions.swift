//
//  Repository+PostCreateActions.swift
//  aizen
//

import Foundation
import CoreData
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen.app", category: "Repository+PostCreateActions")

extension Repository {

    /// Get post-create actions for this repository
    var postCreateActions: [PostCreateAction] {
        get {
            guard let data = postCreateActionsData else { return [] }
            do {
                return try JSONDecoder().decode([PostCreateAction].self, from: data)
            } catch {
                logger.error("Failed to decode post-create actions: \(error.localizedDescription)")
                return []
            }
        }
        set {
            do {
                postCreateActionsData = try JSONEncoder().encode(newValue)
            } catch {
                logger.error("Failed to encode post-create actions: \(error.localizedDescription)")
            }
        }
    }

    /// Check if repository has any enabled post-create actions
    var hasEnabledPostCreateActions: Bool {
        postCreateActions.contains { $0.enabled }
    }

    /// Apply a template to this repository
    func applyTemplate(_ template: PostCreateTemplate) {
        postCreateActions = template.actions
    }

    /// Add a single action
    func addPostCreateAction(_ action: PostCreateAction) {
        var actions = postCreateActions
        actions.append(action)
        postCreateActions = actions
    }

    /// Remove an action by ID
    func removePostCreateAction(id: UUID) {
        var actions = postCreateActions
        actions.removeAll { $0.id == id }
        postCreateActions = actions
    }

    /// Update an action
    func updatePostCreateAction(_ action: PostCreateAction) {
        var actions = postCreateActions
        if let index = actions.firstIndex(where: { $0.id == action.id }) {
            actions[index] = action
            postCreateActions = actions
        }
    }

    /// Reorder actions
    func movePostCreateAction(from source: IndexSet, to destination: Int) {
        var actions = postCreateActions
        // Manual move implementation to avoid SwiftUI dependency
        let items = source.map { actions[$0] }
        for index in source.sorted().reversed() {
            actions.remove(at: index)
        }
        let insertIndex = destination > source.first! ? destination - source.count : destination
        actions.insert(contentsOf: items, at: insertIndex)
        postCreateActions = actions
    }
}
