//
//  ChatActions.swift
//  aizen
//
//  Chat keyboard shortcut actions
//

import SwiftUI

final class ChatActions {
    private var cycleModeForwardHandler: (() -> Void)?

    func configure(cycleModeForward: @escaping () -> Void) {
        cycleModeForwardHandler = cycleModeForward
    }

    func clear() {
        cycleModeForwardHandler = nil
    }

    func cycleModeForward() {
        cycleModeForwardHandler?()
    }
}

struct ChatActionsKey: FocusedValueKey {
    typealias Value = ChatActions
}

extension FocusedValues {
    var chatActions: ChatActions? {
        get { self[ChatActionsKey.self] }
        set { self[ChatActionsKey.self] = newValue }
    }
}
