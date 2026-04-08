//
//  ChatInputBar.swift
//  aizen
//
//  Chat input bar with attachments, voice, and model selection
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import os.log

struct ChatInputBar: View {
    enum Layout {
        static let containerPadding: CGFloat = 10
        static let rowSpacing: CGFloat = 8
        static let controlSize: CGFloat = 34
        static let attachmentControlSize: CGFloat = 30
        static let iconSize: CGFloat = 15
        static let textTopInset: CGFloat = 4
        static let textLeadingInset: CGFloat = 10
        static let minHeightNormal: CGFloat = 50
        static let minHeightVoice: CGFloat = 50
        static let cornerRadiusNormal: CGFloat = 22
        static let cornerRadiusVoice: CGFloat = 20
        static let textMinHeight: CGFloat = 44
        static let textMaxHeight: CGFloat = 140
    }

    let logger = Logger.chat
    @Binding var inputText: String
    @Binding var pendingCursorPosition: Int?
    @Binding var attachments: [ChatAttachment]
    @Binding var isProcessing: Bool
    @Binding var showingVoiceRecording: Bool
    @Binding var showingPermissionError: Bool
    @Binding var permissionErrorMessage: String

    let worktreePath: String
    let session: ChatAgentSession?
    let currentModeId: String?
    let selectedAgent: String
    let isSessionReady: Bool
    let isRestoringSession: Bool
    let audioService: AudioService
    @ObservedObject var autocompleteHandler: UnifiedAutocompleteHandler

    let onSend: () -> Void
    let onCancel: () -> Void
    let onAutocompleteSelect: () -> Void
    let onImagePaste: (Data, String) -> Void
    let onFilePaste: (URL) -> Void
    let onAgentSelect: (String) -> Void

    @State var measuredTextHeight: CGFloat = 0
    @State var isTextEditorFocused = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.scenePhase) var scenePhase
    let disableAnimatedBordersForPerfProbe = false

    let processingGradientColors: [Color] = [
        .accentColor.opacity(0.7), .accentColor.opacity(0.4), .accentColor.opacity(0.7)
    ]
    let planGradientColors: [Color] = [
        Color.blue.opacity(0.9), Color.blue.opacity(0.5), Color.blue.opacity(0.9)
    ]

    var placeholderText: LocalizedStringKey {
        if isSessionReady {
            return "Ask anything, @ to add files, / for commands"
        }
        return isRestoringSession ? "chat.session.restoring" : "chat.session.starting"
    }
}
