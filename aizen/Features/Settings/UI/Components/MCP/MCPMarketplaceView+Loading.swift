import Foundation

extension MCPMarketplaceView {
    func loadServers() async {
        isLoading = true
        errorMessage = nil

        print("[MCPMarketplace] Loading servers...")

        do {
            let result = try await MCPRegistryService.shared.listServers(limit: 50)
            servers = deduplicatedCompatibleServers(from: result)
            hasMore = result.metadata.hasMore
            nextCursor = result.metadata.nextCursor
            print("[MCPMarketplace] Loaded \(servers.count) servers, hasMore: \(hasMore)")
        } catch {
            print("[MCPMarketplace] Error loading servers: \(error)")
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func searchImmediately() async {
        await updateSearchResults(for: searchQuery, debounce: false)
    }

    func updateSearchResults(for query: String, debounce: Bool = true) async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)

        guard !trimmedQuery.isEmpty else {
            await loadServers()
            return
        }

        if debounce {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            guard searchQuery == query else { return }
        }

        isLoading = true
        errorMessage = nil

        print("[MCPMarketplace] Searching for: \(query)")

        do {
            let result = try await MCPRegistryService.shared.search(query: query, limit: 50)
            servers = deduplicatedCompatibleServers(from: result)
            hasMore = result.metadata.hasMore
            nextCursor = result.metadata.nextCursor
            print("[MCPMarketplace] Found \(servers.count) servers")
        } catch {
            print("[MCPMarketplace] Search error: \(error)")
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func loadMore() async {
        guard let cursor = nextCursor, !isLoading else { return }

        isLoading = true

        print("[MCPMarketplace] Loading more with cursor: \(cursor)")

        do {
            let result: MCPSearchResult
            if searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                result = try await MCPRegistryService.shared.listServers(limit: 50, cursor: cursor)
            } else {
                result = try await MCPRegistryService.shared.search(query: searchQuery, limit: 50, cursor: cursor)
            }

            let newServers = compatibleServers(from: result)
            let existingNames = Set(servers.map(\.name))
            let uniqueNew = newServers.filter { !existingNames.contains($0.name) }
            servers.append(contentsOf: uniqueNew)
            hasMore = result.metadata.hasMore
            nextCursor = result.metadata.nextCursor
            print("[MCPMarketplace] Added \(uniqueNew.count) more servers, total: \(servers.count)")
        } catch {
            print("[MCPMarketplace] Load more error: \(error)")
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func deduplicatedCompatibleServers(from result: MCPSearchResult) -> [MCPServer] {
        let filtered = compatibleServers(from: result)
        var seen = Set<String>()
        return filtered.filter { seen.insert($0.name).inserted }
    }

    private func compatibleServers(from result: MCPSearchResult) -> [MCPServer] {
        result.servers
            .map(\.server)
            .filter { server in
                (server.packages != nil && !server.packages!.isEmpty) ||
                (server.remotes != nil && !server.remotes!.isEmpty)
            }
    }
}
