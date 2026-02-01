//
//  PermissionNotificationManager.swift
//  aizen
//
//  Handles macOS notifications for agent permission requests when app is not focused.
//

import ACP
import Foundation
import UserNotifications
import AppKit
import os.log

extension Notification.Name {
    static let navigateToChatSession = Notification.Name("navigateToChatSession")
    static let switchToChatSession = Notification.Name("switchToChatSession")
}

struct PermissionNotificationInfo {
    let chatSessionId: UUID
    let worktreeName: String
    let message: String
    let options: [PermissionOption]
}

@MainActor
final class PermissionNotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PermissionNotificationManager()

    private let center = UNUserNotificationCenter.current()
    private let logger = Logger.forCategory("PermissionNotification")
    private var permissionRequested = false

    /// Pending permission info keyed by notification identifier
    private var pendingNotifications: [String: PermissionNotificationInfo] = [:]

    /// Routes permission response to the correct handler via ChatSessionManager
    private func respondToPermission(chatSessionId: UUID, optionId: String) {
        guard let agentSession = ChatSessionManager.shared.getAgentSession(for: chatSessionId) else {
            return
        }
        agentSession.permissionHandler.respondToPermission(optionId: optionId)
    }

    private override init() {
        super.init()
        center.delegate = self
        registerCategories()
    }

    private func registerCategories() {
        // Define actions for permission notifications
        let allowAction = UNNotificationAction(
            identifier: "ALLOW",
            title: String(localized: "permission.action.allow"),
            options: [.foreground]
        )
        let denyAction = UNNotificationAction(
            identifier: "DENY",
            title: String(localized: "permission.action.deny"),
            options: []
        )
        let viewAction = UNNotificationAction(
            identifier: "VIEW",
            title: String(localized: "permission.action.view"),
            options: [.foreground]
        )

        let category = UNNotificationCategory(
            identifier: "PERMISSION_REQUEST",
            actions: [allowAction, denyAction, viewAction],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([category])
    }

    func notify(info: PermissionNotificationInfo) {
        // Only notify if app is not active
        guard !NSApp.isActive else { return }

        Task {
            guard await requestPermissionIfNeeded() else { return }
            postNotification(info: info)
        }
    }

    private func postNotification(info: PermissionNotificationInfo) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "permission.notification.title \(info.worktreeName)")
        content.body = info.message.isEmpty
            ? String(localized: "permission.notification.body.default")
            : info.message
        content.sound = .default
        content.categoryIdentifier = "PERMISSION_REQUEST"

        // Store session info in userInfo
        content.userInfo = [
            "chatSessionId": info.chatSessionId.uuidString
        ]

        let identifier = UUID().uuidString
        pendingNotifications[identifier] = info

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )

        Task {
            do {
                try await center.add(request)
            } catch {
                logger.error("Failed to deliver permission notification: \(error.localizedDescription)")
            }
        }
    }

    /// Remove pending notification when permission is handled
    func clearNotification(for chatSessionId: UUID) {
        let identifiersToRemove = pendingNotifications
            .filter { $0.value.chatSessionId == chatSessionId }
            .map { $0.key }

        for id in identifiersToRemove {
            pendingNotifications.removeValue(forKey: id)
        }

        center.removeDeliveredNotifications(withIdentifiers: identifiersToRemove)
        center.removePendingNotificationRequests(withIdentifiers: identifiersToRemove)
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Show notifications even when app is in foreground (for edge cases)
        return [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let identifier = response.notification.request.identifier
        let userInfo = response.notification.request.content.userInfo

        guard let sessionIdString = userInfo["chatSessionId"] as? String,
              let chatSessionId = UUID(uuidString: sessionIdString) else {
            return
        }

        await MainActor.run {
            handleNotificationResponse(
                actionIdentifier: response.actionIdentifier,
                chatSessionId: chatSessionId,
                notificationId: identifier
            )
        }
    }

    private func handleNotificationResponse(
        actionIdentifier: String,
        chatSessionId: UUID,
        notificationId: String
    ) {
        let info = pendingNotifications[notificationId]

        switch actionIdentifier {
        case "ALLOW":
            // Prefer allow_once for quick action from notification
            let allowOption = info?.options.first(where: { $0.kind == "allow_once" })
                ?? info?.options.first(where: { $0.kind.contains("allow") })
            if let allowOption {
                respondToPermission(chatSessionId: chatSessionId, optionId: allowOption.optionId)
            } else {
                // Fallback - bring app to front and navigate
                NSApp.activate(ignoringOtherApps: true)
                postNavigationNotification(chatSessionId: chatSessionId)
            }

        case "DENY":
            // Prefer reject_once for quick action from notification
            let denyOption = info?.options.first(where: { $0.kind == "reject_once" })
                ?? info?.options.first(where: { $0.kind.contains("reject") })
            if let denyOption {
                respondToPermission(chatSessionId: chatSessionId, optionId: denyOption.optionId)
            }

        case "VIEW", UNNotificationDefaultActionIdentifier:
            // User clicked the notification - bring app to front and navigate to chat
            NSApp.activate(ignoringOtherApps: true)
            postNavigationNotification(chatSessionId: chatSessionId)

        default:
            break
        }

        pendingNotifications.removeValue(forKey: notificationId)
    }

    private func postNavigationNotification(chatSessionId: UUID) {
        NotificationCenter.default.post(
            name: .navigateToChatSession,
            object: nil,
            userInfo: ["chatSessionId": chatSessionId]
        )
    }

    private func requestPermissionIfNeeded() async -> Bool {
        if permissionRequested {
            let settings = await center.notificationSettings()
            return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        }
        permissionRequested = true
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }
}
