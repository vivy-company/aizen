//
//  SessionRowSummaryBuilder.swift
//  aizen
//

import ACP
import Foundation

enum SessionRowSummaryBuilder {
    static func summary(for session: ChatSession) -> String {
        guard let messages = session.messages as? Set<ChatMessage> else {
            return "No messages yet"
        }

        let latestMessage = messages
            .filter { $0.role == "user" }
            .max { lhs, rhs in
                let lhsTime = lhs.timestamp ?? Date.distantPast
                let rhsTime = rhs.timestamp ?? Date.distantPast
                return lhsTime < rhsTime
            }

        guard let latestMessage,
              let contentJSON = latestMessage.contentJSON else {
            return "No user messages yet"
        }

        guard let contentData = contentJSON.data(using: .utf8) else {
            return "Unable to load message"
        }

        guard let contentBlocks = try? JSONDecoder().decode([ContentBlock].self, from: contentData) else {
            return contentJSON
        }

        let text = contentBlocks.compactMap { block -> String? in
            guard case .text(let textContent) = block else { return nil }
            return textContent.text
        }
        .joined(separator: " ")

        guard !text.isEmpty else {
            return "Empty message"
        }

        let maxLength = 120
        guard text.count > maxLength else {
            return text
        }

        return String(text.prefix(maxLength)) + "..."
    }
}
