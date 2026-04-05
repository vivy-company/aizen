//
//  ChatSessionStore+Observation.swift
//  aizen
//
//  Created by OpenAI Codex on 03.04.26.
//

import Combine
import ACP
import Foundation
import SwiftUI

@MainActor
extension ChatSessionStore {
    func setupNotificationObservers() {
        NotificationCenter.default.publisher(for: .cycleModeShortcut)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.cycleModeForward()
            }
            .store(in: &notificationCancellables)

        NotificationCenter.default.publisher(for: .interruptAgentShortcut)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.cancelCurrentPrompt()
            }
            .store(in: &notificationCancellables)
    }

}
