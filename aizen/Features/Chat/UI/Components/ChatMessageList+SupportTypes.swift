//
//  ChatMessageList+SupportTypes.swift
//  aizen
//
//  Created by OpenAI Codex on 03.04.26.
//

import AppKit
import SwiftUI
import VVChatTimeline

enum ToolDiffPreviewLineType {
    case context
    case added
    case deleted
    case separator
}

struct ToolDiffPreviewLine {
    let type: ToolDiffPreviewLineType
    let content: String
}

struct ChatTimelineHost: NSViewRepresentable {
    let controller: VVChatTimelineController
    let scrollRequest: ChatTimelineStore.ScrollRequest?
    let onStateChange: (VVChatTimelineState) -> Void
    let onUserMessageCopyAction: (String) -> Void
    let onUserMessageCopyHoverChange: (String?) -> Void
    let onEntryActivate: (String) -> Void
    let onLinkActivate: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> VVChatTimelineView {
        let view = VVChatTimelineView(frame: .zero)
        view.controller = controller
        view.onStateChange = onStateChange
        view.onUserMessageCopyAction = onUserMessageCopyAction
        view.onUserMessageCopyHoverChange = onUserMessageCopyHoverChange
        view.onEntryActivate = onEntryActivate
        view.onLinkActivate = onLinkActivate
        return view
    }

    func updateNSView(_ nsView: VVChatTimelineView, context: Context) {
        if nsView.controller !== controller {
            nsView.controller = controller
        }
        nsView.onStateChange = onStateChange
        nsView.onUserMessageCopyAction = onUserMessageCopyAction
        nsView.onUserMessageCopyHoverChange = onUserMessageCopyHoverChange
        nsView.onEntryActivate = onEntryActivate
        nsView.onLinkActivate = onLinkActivate

        if context.coordinator.lastHandledScrollRequestID != scrollRequest?.id {
            context.coordinator.lastHandledScrollRequestID = scrollRequest?.id
            context.coordinator.handleScrollRequest(scrollRequest, in: nsView, controller: controller)
        }
    }

    @MainActor
    final class Coordinator {
        var lastHandledScrollRequestID: UUID?

        func handleScrollRequest(
            _ request: ChatTimelineStore.ScrollRequest?,
            in view: VVChatTimelineView,
            controller: VVChatTimelineController
        ) {
            guard let request else { return }

            switch request.target {
            case .bottom:
                if request.animated {
                    view.jumpToLatestAnimated()
                } else {
                    controller.jumpToLatest()
                }
            }
        }
    }
}
