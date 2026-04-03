//
//  XcodeBuildStore+SelectionPersistence.swift
//  aizen
//
//  Scheme and destination persistence
//

import Foundation

extension XcodeBuildStore {
    nonisolated static func persistenceKey(prefix: String, scopedTo path: String) -> String {
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        return "\(prefix)_\(normalizedPath)"
    }

    var lastDestinationIdKey: String {
        guard let path = currentWorktreePath else { return "" }
        return Self.persistenceKey(prefix: "xcodeLastDestinationId", scopedTo: path)
    }

    var projectSchemeKey: String {
        guard let project = detectedProject else { return "" }
        return Self.persistenceKey(prefix: "xcodeScheme", scopedTo: project.path)
    }

    var destinationsCacheKey: String {
        guard let path = currentWorktreePath else { return "" }
        return Self.persistenceKey(prefix: "xcodeDestinationsCache", scopedTo: path)
    }

    func selectScheme(_ scheme: String) {
        selectedScheme = scheme
        guard !projectSchemeKey.isEmpty else { return }
        UserDefaults.standard.set(scheme, forKey: projectSchemeKey)
    }

    func selectDestination(_ destination: XcodeDestination) {
        selectedDestination = destination
        guard !lastDestinationIdKey.isEmpty else { return }
        UserDefaults.standard.set(destination.id, forKey: lastDestinationIdKey)
    }
}
