//
//  MCPRegistryService.swift
//  aizen
//
//  API client for MCP Registry
//

import Foundation

actor MCPRegistryService {
    static let shared = MCPRegistryService()

    private let baseURL = "https://registry.modelcontextprotocol.io/v0"
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    // MARK: - Search

    func search(query: String, limit: Int = 20, cursor: String? = nil) async throws -> MCPSearchResult {
        var components = URLComponents(string: "\(baseURL)/servers")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "version", value: "latest")
        ]

        if let cursor = cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            throw MCPRegistryError.invalidURL
        }

        return try await fetch(url: url)
    }

    // MARK: - List

    func listServers(limit: Int = 20, cursor: String? = nil) async throws -> MCPSearchResult {
        var components = URLComponents(string: "\(baseURL)/servers")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "version", value: "latest")
        ]

        if let cursor = cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            throw MCPRegistryError.invalidURL
        }

        return try await fetch(url: url)
    }

    // MARK: - Get Server

    func getServer(name: String) async throws -> MCPServer {
        let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        let url = URL(string: "\(baseURL)/servers/\(encodedName)")!

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MCPRegistryError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 404 {
                throw MCPRegistryError.serverNotFound(name)
            }
            throw MCPRegistryError.httpError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(MCPServer.self, from: data)
    }

    // MARK: - Private

    private func fetch(url: URL) async throws -> MCPSearchResult {
        print("[MCPRegistry] Fetching: \(url)")

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MCPRegistryError.invalidResponse
        }

        print("[MCPRegistry] Response status: \(httpResponse.statusCode)")

        guard httpResponse.statusCode == 200 else {
            throw MCPRegistryError.httpError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        do {
            let result = try decoder.decode(MCPSearchResult.self, from: data)
            print("[MCPRegistry] Decoded \(result.servers.count) servers, hasMore: \(result.metadata.hasMore ?? false)")
            return result
        } catch {
            print("[MCPRegistry] Decoding error: \(error)")
            if let jsonString = String(data: data.prefix(500), encoding: .utf8) {
                print("[MCPRegistry] Response preview: \(jsonString)")
            }
            throw MCPRegistryError.decodingError(error)
        }
    }
}

// MARK: - Errors

enum MCPRegistryError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case serverNotFound(String)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .serverNotFound(let name):
            return "Server not found: \(name)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        }
    }
}
