//
//  ChatAgentSession+Shutdown.swift
//  aizen
//
//  Session shutdown and cleanup helpers.
//

import ACP
import Combine
import CoreData
import Foundation
import UniformTypeIdentifiers

@MainActor
extension ChatAgentSession {
    func close() async {
        notificationTask?.cancel()
        notificationTask = nil

        notificationProcessingTask?.cancel()
        notificationProcessingTask = nil

        versionCheckTask?.cancel()
        versionCheckTask = nil

        resetFinalizeState()
        clearThoughtBuffer()
        clearAgentMessageBuffer()

        isStreaming = false
        isActive = false
        isResumingSession = false

        await terminalDelegate.cleanup()

        if let client = acpClient {
            await client.setDelegate(nil)
            await client.terminate()
        }

        acpClient = nil
        sessionState = .idle
    }
}
