//
//  ChatSessionViewModel+Attachments.swift
//  aizen
//
//  Attachment handling for chat sessions
//

import Foundation
import SwiftUI

extension ChatSessionViewModel {
    // MARK: - Attachment Management

    func removeAttachment(_ attachment: ChatAttachment) {
        guard let index = attachments.firstIndex(of: attachment) else { return }
        removeAttachment(at: index)
    }

    func removeAttachment(at index: Int) {
        guard attachments.indices.contains(index) else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            attachments.remove(at: index)
        }
    }

    func addFileAttachment(_ url: URL) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            attachments.append(.file(url))
        }
    }

    func addReviewCommentsAttachment(_ markdown: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            attachments.append(.reviewComments(markdown))
        }
    }
}
