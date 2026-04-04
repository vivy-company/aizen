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

    private let logger = Logger.chat
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) var scenePhase
    let disableAnimatedBordersForPerfProbe = false

    private let processingGradientColors: [Color] = [
        .accentColor.opacity(0.7), .accentColor.opacity(0.4), .accentColor.opacity(0.7)
    ]
    private let planGradientColors: [Color] = [
        Color.blue.opacity(0.9), Color.blue.opacity(0.5), Color.blue.opacity(0.9)
    ]

    private var placeholderText: LocalizedStringKey {
        if isSessionReady {
            return "Ask anything, @ to add files, / for commands"
        }
        return isRestoringSession ? "chat.session.restoring" : "chat.session.starting"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                if showingVoiceRecording {
                    VoiceRecordingView(
                        audioService: audioService,
                        onSend: { transcribedText in
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                showingVoiceRecording = false
                                inputText = transcribedText
                            }
                        },
                        onCancel: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                showingVoiceRecording = false
                            }
                        }
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
                } else {
                    if inputText.isEmpty {
                        Text(placeholderText)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .padding(.top, Layout.textTopInset)
                            .padding(.leading, Layout.textLeadingInset)
                            .allowsHitTesting(false)
                    }

                    CustomTextEditor(
                        text: $inputText,
                        measuredHeight: $measuredTextHeight,
                        isFocused: $isTextEditorFocused,
                        textInset: Layout.textLeadingInset,
                        textTopInset: Layout.textTopInset,
                        onSubmit: {
                            if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                onSend()
                            }
                        },
                        onCursorChange: { text, cursorPosition, cursorRect in
                            autocompleteHandler.handleTextChange(
                                text: text,
                                cursorPosition: cursorPosition,
                                cursorRect: cursorRect
                            )
                        },
                        onAutocompleteNavigate: { action in
                            handleAutocompleteNavigation(action)
                        },
                        onImagePaste: onImagePaste,
                        onFilePaste: onFilePaste,
                        onLargeTextPaste: { pastedText in
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                attachments.append(.text(pastedText))
                            }
                        },
                        pendingCursorPosition: $pendingCursorPosition
                    )
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .frame(height: textEditorHeight)
                    .disabled(!isSessionReady)
                }
            }
            .frame(
                maxWidth: .infinity,
                minHeight: showingVoiceRecording ? Layout.minHeightVoice : Layout.minHeightNormal,
                alignment: .leading
            )

            if !showingVoiceRecording {
                controlsRow
                .padding(.top, 4)
            }
        }
        .padding(Layout.containerPadding)
        .background { composerBackground }
        .overlay {
            if isProcessing {
                AnimatedGradientBorder(
                    cornerRadius: inputCornerRadius,
                    colors: currentModeId == "plan" ? planGradientColors : processingGradientColors,
                    dashed: false,
                    reduceMotion: reduceMotion,
                    isActive: shouldAnimateBorder
                )
                .allowsHitTesting(false)
            } else if currentModeId != "plan" {
                RoundedRectangle(cornerRadius: inputCornerRadius, style: .continuous)
                    .strokeBorder(.separator.opacity(isTextEditorFocused ? 0.45 : 0.2), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }

            if currentModeId == "plan" && !isProcessing {
                AnimatedGradientBorder(
                    cornerRadius: inputCornerRadius,
                    colors: planGradientColors,
                    dashed: true,
                    reduceMotion: reduceMotion,
                    isActive: shouldAnimateBorder
                )
                .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private var composerBackground: some View {
        let shape = RoundedRectangle(cornerRadius: inputCornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            GlassEffectContainer {
                shape
                    .fill(.white.opacity(0.001))
                    .glassEffect(.regular, in: shape)
                shape
                    .fill(.white.opacity(0.035))
            }
        } else {
            shape.fill(.ultraThinMaterial)
        }
    }

}
