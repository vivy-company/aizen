//
//  GitHubWorkflowResponseTypes.swift
//  aizen
//
//  Response DTOs for GitHub workflow CLI JSON payloads
//

import Foundation

struct GitHubWorkflowResponse: Decodable {
    let id: Int
    let name: String
    let path: String
    let state: String
}

struct GitHubRunResponse: Decodable {
    let databaseId: Int
    let workflowDatabaseId: Int?
    let workflowName: String
    let number: Int
    let status: String
    let conclusion: String?
    let headBranch: String
    let headSha: String
    let event: String
    let createdAt: Date?
    let updatedAt: Date?
    let url: String?
    let displayTitle: String?
}

struct GitHubJobsResponse: Decodable {
    let jobs: [GitHubJob]
}

struct GitHubJob: Decodable {
    let databaseId: Int
    let name: String
    let status: String
    let conclusion: String?
    let startedAt: Date?
    let completedAt: Date?
    let steps: [GitHubStep]
}

struct GitHubStep: Decodable {
    let number: Int
    let name: String
    let status: String
    let conclusion: String?
    let startedAt: Date?
    let completedAt: Date?
}
