//
//  SplitTerminalSubtreeView.swift
//  aizen
//

import SwiftUI

struct SplitTerminalSubtreeView: View {
    let node: SplitNode
    @ObservedObject var worktree: Worktree
    @ObservedObject var session: TerminalSession
    let sessionManager: TerminalRuntimeStore
    let effectiveThemeName: String
    let isSplit: Bool
    let focusedPaneId: String
    @Binding var voiceAction: (paneId: String, action: VoiceAction)?
    let focusRequestVersion: Int
    let onFocus: (String) -> Void
    let onProcessExit: (String) -> Void
    let onTitleChange: (String, String) -> Void
    let onVoiceRecordingChanged: (String, Bool) -> Void
    let onResizeSplit: (SplitNode, CGFloat) -> Void
    let onEqualize: () -> Void

    var body: some View {
        switch node {
        case .leaf(let paneId):
            let voiceActionBinding = Binding<VoiceAction?>(
                get: { voiceAction?.paneId == paneId ? voiceAction?.action : nil },
                set: { _ in voiceAction = nil }
            )

            TerminalPaneView(
                worktree: worktree,
                session: session,
                paneId: paneId,
                effectiveThemeName: effectiveThemeName,
                isSplit: isSplit,
                isFocused: focusedPaneId == paneId,
                sessionManager: sessionManager,
                voiceAction: voiceActionBinding,
                focusRequestVersion: focusRequestVersion,
                onFocus: { onFocus(paneId) },
                onProcessExit: { onProcessExit(paneId) },
                onTitleChange: { onTitleChange(paneId, $0) },
                onVoiceRecordingChanged: { onVoiceRecordingChanged(paneId, $0) }
            )

        case .split(let split):
            SplitView(
                split.direction == .horizontal ? .horizontal : .vertical,
                .init(
                    get: { CGFloat(split.ratio) },
                    set: { onResizeSplit(node, $0) }
                ),
                dividerColor: Color(nsColor: GhosttyThemeParser.loadDividerColor(named: effectiveThemeName)),
                left: {
                    SplitTerminalSubtreeView(
                        node: split.left,
                        worktree: worktree,
                        session: session,
                        sessionManager: sessionManager,
                        effectiveThemeName: effectiveThemeName,
                        isSplit: true,
                        focusedPaneId: focusedPaneId,
                        voiceAction: $voiceAction,
                        focusRequestVersion: focusRequestVersion,
                        onFocus: onFocus,
                        onProcessExit: onProcessExit,
                        onTitleChange: onTitleChange,
                        onVoiceRecordingChanged: onVoiceRecordingChanged,
                        onResizeSplit: onResizeSplit,
                        onEqualize: onEqualize
                    )
                },
                right: {
                    SplitTerminalSubtreeView(
                        node: split.right,
                        worktree: worktree,
                        session: session,
                        sessionManager: sessionManager,
                        effectiveThemeName: effectiveThemeName,
                        isSplit: true,
                        focusedPaneId: focusedPaneId,
                        voiceAction: $voiceAction,
                        focusRequestVersion: focusRequestVersion,
                        onFocus: onFocus,
                        onProcessExit: onProcessExit,
                        onTitleChange: onTitleChange,
                        onVoiceRecordingChanged: onVoiceRecordingChanged,
                        onResizeSplit: onResizeSplit,
                        onEqualize: onEqualize
                    )
                },
                onEqualize: onEqualize
            )
        }
    }
}
