//
//  ChatSessionView+InteractionSupport.swift
//  aizen
//
//  Permission and send-message interaction helpers.
//

import ACP
import Foundation

extension ChatSessionView {
    var currentPermissionRequest: RequestPermissionRequest? {
        guard viewModel.showingPermissionAlert,
              let request = viewModel.currentPermissionRequest else {
            return nil
        }
        return request
    }

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)

        if ClientCommandHandler.shared.handle(text, context: viewContext) {
            inputText = ""
            return
        }

        inputText = ""
        viewModel.sendMessage(text)
    }
}
