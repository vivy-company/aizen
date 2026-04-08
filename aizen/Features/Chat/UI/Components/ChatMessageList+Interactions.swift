//
//  ChatMessageList+Interactions.swift
//  aizen
//
//  Created by OpenAI Codex on 03.04.26.
//

import AppKit
import Foundation
import VVChatTimeline

extension ChatMessageList {
    func handleUserMessageCopyHoverChange(_ messageID: String?) {
        guard hoveredCopyUserMessageID != messageID else { return }
        hoveredCopyUserMessageID = messageID
    }
}
