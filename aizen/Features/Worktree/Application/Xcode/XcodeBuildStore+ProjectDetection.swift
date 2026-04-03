//
//  XcodeBuildStore+ProjectDetection.swift
//  aizen
//
//  Project discovery and bootstrap
//

import Foundation

extension XcodeBuildStore {
    func detectProject(at path: String) {
        if path == currentWorktreePath, detectedProject != nil {
            return
        }
        guard path != currentWorktreePath else { return }
        currentWorktreePath = path
        let projectDetector = self.projectDetector
        let destinationsCacheKey = self.destinationsCacheKey
        let lastDestinationIdKey = self.lastDestinationIdKey

        Task { [weak self] in
            guard let self = self else { return }

            await MainActor.run {
                self.detectedProject = nil
                self.selectedScheme = nil
                self.currentPhase = .idle
                self.lastBuildLog = nil
                self.isReady = false
            }

            let project = await projectDetector.detectProject(at: path)
            guard let project = project else { return }

            let cachedDestinations = Self.loadCachedDestinationsOffMainActor(from: destinationsCacheKey)
            let lastDestId = Self.loadLastDestinationId(from: lastDestinationIdKey)
            let savedScheme = self.loadSavedScheme(for: project.path)

            await MainActor.run {
                if let cached = cachedDestinations {
                    self.availableDestinations = cached
                }

                self.detectedProject = project

                if let saved = savedScheme, project.schemes.contains(saved) {
                    self.selectedScheme = saved
                } else {
                    self.selectedScheme = project.schemes.first
                }

                if !lastDestId.isEmpty, let dest = self.findDestination(byId: lastDestId) {
                    self.selectedDestination = dest
                } else if self.selectedDestination == nil {
                    self.selectedDestination = self.availableDestinations[.simulator]?.first { $0.platform == "iOS" }
                        ?? self.availableDestinations[.mac]?.first
                }

                if !self.availableDestinations.isEmpty {
                    self.isReady = true
                }
            }

            let shouldRefresh = await MainActor.run { self.shouldRefreshDestinations(force: false) }
            if cachedDestinations != nil, shouldRefresh {
                await self.loadDestinations(force: false)
            } else {
                await self.loadDestinations(force: true)
                await MainActor.run {
                    self.isReady = true
                }
            }
        }
    }

    nonisolated func loadSavedScheme(for projectPath: String) -> String? {
        let key = Self.persistenceKey(prefix: "xcodeScheme", scopedTo: projectPath)
        return UserDefaults.standard.string(forKey: key)
    }
}
