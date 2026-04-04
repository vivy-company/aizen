//
//  GitLabWorkflowResponseTypes.swift
//  aizen
//

import Foundation

struct GitLabPipelineResponse: Decodable {
    let id: Int
    let ref: String
    let sha: String
    let status: String
    let source: String?
    let createdAt: Date?
    let updatedAt: Date?
    let webUrl: String?
    let user: GitLabUser?
}

struct GitLabUser: Decodable {
    let username: String
}

struct GitLabJobResponse: Decodable {
    let id: Int
    let name: String
    let status: String
    let stage: String
    let startedAt: Date?
    let finishedAt: Date?
    let webUrl: String?
}
