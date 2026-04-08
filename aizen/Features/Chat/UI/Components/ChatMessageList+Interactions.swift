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
    func handleTimelineLinkActivate(_ rawLink: String) {
        guard let url = URL(string: rawLink) else { return }

        switch url.scheme?.lowercased() {
        case "aizen-file":
            guard let path = destinationPath(from: url) else { return }
            NotificationCenter.default.post(
                name: .openFileInEditor,
                object: nil,
                userInfo: ["path": path]
            )
        case "aizen":
            DeepLinkHandler.shared.handle(url)
        default:
            NSWorkspace.shared.open(url)
        }
    }

    func handleUserMessageCopyHoverChange(_ messageID: String?) {
        guard hoveredCopyUserMessageID != messageID else { return }
        hoveredCopyUserMessageID = messageID
    }
}
