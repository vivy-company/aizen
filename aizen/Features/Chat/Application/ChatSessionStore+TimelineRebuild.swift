//
//  ChatSessionStore+TimelineRebuild.swift
//  aizen
//
//  Created by OpenAI Codex on 05.04.26.
//

import ACP
import Foundation
import SwiftUI

@MainActor
extension ChatSessionStore {
    static func hasEquivalentMessageEnvelope(_ lhs: [MessageItem], _ rhs: [MessageItem]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        guard let left = lhs.last, let right = rhs.last else {
            return lhs.isEmpty && rhs.isEmpty
        }

        let leftTail = left.content.suffix(64)
        let rightTail = right.content.suffix(64)
        return left.id == right.id
            && left.isComplete == right.isComplete
            && left.content.count == right.content.count
            && leftTail == rightTail
            && left.contentBlocks.count == right.contentBlocks.count
    }

    func resetTimelineSyncState() {
        timelineStore.resetSyncState()

        skipNextMessagesEmission = false
        skipNextToolCallsEmission = false
    }

    func bootstrapTimelineState(from session: ChatAgentSession) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            timelineStore.bootstrap(from: session)
        }
    }
}
