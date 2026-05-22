//
//  ChatSessionStore+Analytics.swift
//  aizen
//
//  Content-free analytics hooks for chat session lifecycle.
//

import Foundation

extension ChatSessionStore {
    func trackAgentSessionStarted(hasAttachments: Bool) {
        Analytics.shared.track(
            .agentSessionStarted(
                provider: .provider(forAgentId: selectedAgent),
                entryPoint: .chat,
                hasAttachments: hasAttachments
            )
        )
    }
}
