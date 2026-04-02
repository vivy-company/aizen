//
//  WorktreeSelectionPersistence.swift
//  aizen
//
//  Created by Codex on 03.04.26.
//

import Foundation

enum WorktreeSelectionPersistence {
    static func decodeRepositorySelections(from json: String) -> [String: String] {
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return decoded
    }

    static func encodeRepositorySelections(_ selections: [String: String]) -> String? {
        guard let encoded = try? JSONEncoder().encode(selections) else {
            return nil
        }
        return String(data: encoded, encoding: .utf8)
    }

    static func storedWorktreeId(for repositoryId: String, repositorySelectionsJSON: String) -> UUID? {
        let selections = decodeRepositorySelections(from: repositorySelectionsJSON)
        guard let worktreeIdString = selections[repositoryId] else {
            return nil
        }
        return UUID(uuidString: worktreeIdString)
    }

    static func updatingRepositorySelectionsJSON(
        repositorySelectionsJSON: String,
        repositoryId: String,
        worktreeId: UUID?
    ) -> String? {
        var selections = decodeRepositorySelections(from: repositorySelectionsJSON)
        if let worktreeId {
            selections[repositoryId] = worktreeId.uuidString
        } else {
            selections.removeValue(forKey: repositoryId)
        }
        return encodeRepositorySelections(selections)
    }

    static func decodeMRUOrder(from json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return decoded
    }

    static func encodeMRUOrder(_ order: [String]) -> String? {
        guard let encoded = try? JSONEncoder().encode(order) else {
            return nil
        }
        return String(data: encoded, encoding: .utf8)
    }
}
