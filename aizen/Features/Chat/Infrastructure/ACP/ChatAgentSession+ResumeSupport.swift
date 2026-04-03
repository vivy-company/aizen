//
//  ChatAgentSession+ResumeSupport.swift
//  aizen
//
//  Created by OpenAI Codex on 03.04.26.
//

import Foundation

@MainActor
extension ChatAgentSession {
    func prepareForResume(chatSessionId: UUID) {
        sessionState = .initializing
        isActive = true
        isResumingSession = true
        suppressResumedAgentMessages = true
        prepareResumeReplayState()
        self.chatSessionId = chatSessionId
    }

    func validateResumeRequest(acpSessionId: String, workingDir: String) throws {
        guard !acpSessionId.isEmpty,
              acpSessionId.count < 256,
              acpSessionId.allSatisfy({ $0.isASCII && !$0.isNewline }) else {
            failResume("Invalid ACP session ID format")
            throw AgentSessionError.custom("Invalid ACP session ID format")
        }

        guard FileManager.default.fileExists(atPath: workingDir) else {
            failResume("Working directory no longer exists: \(workingDir)")
            throw AgentSessionError.custom("Working directory no longer exists: \(workingDir)")
        }

        guard FileManager.default.isReadableFile(atPath: workingDir) else {
            failResume("Working directory not accessible: \(workingDir)")
            throw AgentSessionError.custom("Working directory not accessible: \(workingDir)")
        }
    }

    func failResume(_ message: String) {
        resetResumeState()
        sessionState = .failed(message)
    }

    func resetResumeState() {
        isActive = false
        isResumingSession = false
        clearResumeReplayState()
    }

    func scheduleResumeReplayCleanup() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            self.isResumingSession = false
            self.clearResumeReplayState()
        }
    }
}
