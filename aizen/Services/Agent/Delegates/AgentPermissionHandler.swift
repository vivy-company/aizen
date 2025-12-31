//
//  AgentPermissionHandler.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import Foundation
import Combine
import AppKit
import os.log

/// Main actor class responsible for handling permission requests from agents
@MainActor
class AgentPermissionHandler: ObservableObject {

    // MARK: - Published Properties

    @Published var permissionRequest: RequestPermissionRequest?
    @Published var showingPermissionAlert: Bool = false

    // MARK: - Context Properties

    /// The chat session ID this handler belongs to (set by ChatSessionManager)
    var chatSessionId: UUID?
    /// The worktree name for notification display (set by ChatSessionManager)
    var worktreeName: String?

    // MARK: - Private Properties

    private var permissionContinuation: CheckedContinuation<RequestPermissionResponse, Never>?
    private var timeoutTask: Task<Void, Never>?
    private let logger = Logger.forCategory("PermissionHandler")

    /// Timeout for permission requests (5 minutes)
    private let permissionTimeout: Duration = .seconds(300)

    // MARK: - Initialization

    init() {}

    // MARK: - Permission Handling

    /// Handle permission request from agent - suspends until user responds or timeout
    func handlePermissionRequest(request: RequestPermissionRequest) async -> RequestPermissionResponse {
        logger.info("Permission request received: \(request.message ?? "no message")")
        logger.info("Options: \(request.options?.map { $0.optionId }.joined(separator: ", ") ?? "none")")

        // Cancel any existing timeout
        timeoutTask?.cancel()

        return await withCheckedContinuation { continuation in
            self.permissionRequest = request
            self.showingPermissionAlert = true
            self.permissionContinuation = continuation

            // Trigger system notification if app is not active
            self.triggerSystemNotificationIfNeeded(request: request)

            // Start timeout timer
            self.timeoutTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: self?.permissionTimeout ?? .seconds(300))
                    // Timeout reached - auto-deny
                    self?.handleTimeout()
                } catch {
                    // Task cancelled - user responded in time
                }
            }
        }
    }

    private func triggerSystemNotificationIfNeeded(request: RequestPermissionRequest) {
        guard let chatSessionId = chatSessionId else { return }

        let info = PermissionNotificationInfo(
            chatSessionId: chatSessionId,
            worktreeName: worktreeName ?? "Chat",
            message: request.message ?? "",
            options: request.options ?? []
        )

        PermissionNotificationManager.shared.notify(info: info)
    }

    /// Handle timeout - auto-deny the permission request
    private func handleTimeout() {
        guard permissionContinuation != nil else { return }

        logger.warning("Permission request timed out - auto-denying")

        showingPermissionAlert = false
        permissionRequest = nil

        if let continuation = permissionContinuation {
            let outcome = PermissionOutcome(optionId: "deny")
            let response = RequestPermissionResponse(outcome: outcome)
            continuation.resume(returning: response)
            permissionContinuation = nil
        }

        timeoutTask = nil
    }

    /// Respond to a permission request with user's choice
    func respondToPermission(optionId: String) {
        logger.info("Permission response: \(optionId)")

        // Cancel timeout - user responded in time
        timeoutTask?.cancel()
        timeoutTask = nil

        // Clear any pending system notification
        if let sessionId = chatSessionId {
            PermissionNotificationManager.shared.clearNotification(for: sessionId)
        }

        showingPermissionAlert = false
        permissionRequest = nil

        if let continuation = permissionContinuation {
            let outcome = PermissionOutcome(optionId: optionId)
            let response = RequestPermissionResponse(outcome: outcome)
            logger.info("Sending permission response with outcome: \(optionId)")
            continuation.resume(returning: response)
            permissionContinuation = nil
        } else {
            logger.warning("No continuation found for permission response")
        }
    }

    /// Cancel any pending permission request
    func cancelPendingRequest() {
        // Cancel timeout
        timeoutTask?.cancel()
        timeoutTask = nil

        if let continuation = permissionContinuation {
            let outcome = PermissionOutcome(optionId: "deny")
            let response = RequestPermissionResponse(outcome: outcome)
            continuation.resume(returning: response)
            permissionContinuation = nil
        }

        showingPermissionAlert = false
        permissionRequest = nil
    }

    /// Check if there's a pending permission request
    var hasPendingRequest: Bool {
        permissionContinuation != nil
    }
}
