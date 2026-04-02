//
//  ChatAgentSession+ResumeReplay.swift
//  aizen
//
//  Created by OpenAI Codex on 03.04.26.
//

import Foundation

@MainActor
extension ChatAgentSession {
    func prepareResumeReplayState() {
        resumeReplayAgentMessages = messages
            .filter { $0.role == .agent }
            .map(\.content)
        resumeReplayIndex = 0
        resumeReplayBuffer = ""
    }

    func clearResumeReplayState() {
        resumeReplayAgentMessages.removeAll()
        resumeReplayIndex = 0
        resumeReplayBuffer = ""
        suppressResumedAgentMessages = false
    }

    func shouldSkipResumedAgentChunk(text: String, hasContentBlocks: Bool) -> Bool {
        if suppressResumedAgentMessages {
            return true
        }
        guard isResumingSession else { return false }

        guard !text.isEmpty else {
            if hasContentBlocks {
                isResumingSession = false
                clearResumeReplayState()
                return false
            }
            return true
        }

        guard resumeReplayIndex < resumeReplayAgentMessages.count else {
            isResumingSession = false
            clearResumeReplayState()
            return false
        }

        let target = resumeReplayAgentMessages[resumeReplayIndex]
        let candidate = resumeReplayBuffer + text

        if target.hasPrefix(candidate) {
            resumeReplayBuffer = candidate
            if candidate == target {
                resumeReplayIndex += 1
                resumeReplayBuffer = ""
                if resumeReplayIndex >= resumeReplayAgentMessages.count {
                    isResumingSession = false
                    clearResumeReplayState()
                }
            }
            return true
        }

        isResumingSession = false
        clearResumeReplayState()
        return false
    }
}
