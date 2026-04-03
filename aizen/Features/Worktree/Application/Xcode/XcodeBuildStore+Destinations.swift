//
//  XcodeBuildStore+Destinations.swift
//  aizen
//
//  Destination loading, caching, and restoration
//

import Foundation
import os

extension XcodeBuildStore {
    /// Load cached destinations off main actor to avoid UI freeze.
    nonisolated static func loadCachedDestinationsOffMainActor(from key: String) -> [DestinationType: [XcodeDestination]]? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let cached = try? JSONDecoder().decode(CachedDestinations.self, from: data) else {
            return nil
        }
        return cached.toDestinationDict()
    }

    nonisolated static func loadLastDestinationId(from key: String) -> String {
        guard !key.isEmpty else { return "" }
        return UserDefaults.standard.string(forKey: key) ?? ""
    }

    func refreshDestinations() {
        Task { [weak self] in
            await self?.loadDestinations(force: true)
        }
    }

    func cacheDestinations(_ destinations: [DestinationType: [XcodeDestination]]) {
        let allDestinations = destinations.flatMap { type, dests in
            dests.map { CachedDestination(destination: $0, type: type) }
        }
        let cached = CachedDestinations(destinations: allDestinations)

        guard !destinationsCacheKey.isEmpty else { return }

        if let data = try? JSONEncoder().encode(cached) {
            UserDefaults.standard.set(data, forKey: destinationsCacheKey)
        }
    }

    func loadDestinations(force: Bool = false) async {
        guard force || shouldRefreshDestinations(force: false) else { return }

        await MainActor.run {
            isLoadingDestinations = true
        }

        do {
            let destinations = try await deviceService.listDestinations()

            await MainActor.run {
                self.availableDestinations = destinations
                self.cacheDestinations(destinations)
                self.lastDestinationsRefreshAt = Date()

                let lastId = Self.loadLastDestinationId(from: self.lastDestinationIdKey)
                if !lastId.isEmpty,
                   let destination = self.findDestination(byId: lastId) {
                    self.selectedDestination = destination
                } else if self.selectedDestination == nil {
                    self.selectedDestination = destinations[.simulator]?.first { $0.platform == "iOS" }
                        ?? destinations[.mac]?.first
                }
            }
        } catch {
            logger.error("Failed to load destinations: \(error.localizedDescription)")
        }

        await MainActor.run {
            isLoadingDestinations = false
        }
    }

    func shouldRefreshDestinations(force: Bool) -> Bool {
        guard !force else { return true }
        guard let lastRefreshAt = lastDestinationsRefreshAt else { return true }
        return Date().timeIntervalSince(lastRefreshAt) >= destinationsRefreshTTL
    }

    func findDestination(byId id: String) -> XcodeDestination? {
        for (_, destinations) in availableDestinations {
            if let destination = destinations.first(where: { $0.id == id }) {
                return destination
            }
        }
        return nil
    }
}
