//
//  ChatSessionView+Composer.swift
//  aizen
//
//  Composer, attachments, and footer controls stack.
//

import SwiftUI

extension ChatSessionView {
    var composerStack: some View {
        Group {
            if !viewModel.attachments.isEmpty {
                ChatAttachmentsBar(
                    attachments: viewModel.attachments,
                    onRemoveAttachment: { index in
                        viewModel.removeAttachment(at: index)
                    }
                )
                .padding(.horizontal, 20)
            }

            ChatInputBar(
                inputText: $inputText,
                pendingCursorPosition: $pendingCursorPosition,
                attachments: $viewModel.attachments,
                isProcessing: $viewModel.isProcessing,
                showingVoiceRecording: $showingVoiceRecording,
                showingPermissionError: $showingPermissionError,
                permissionErrorMessage: $permissionErrorMessage,
                worktreePath: viewModel.worktree.path ?? "",
                session: viewModel.currentAgentSession,
                currentModeId: viewModel.currentModeId,
                selectedAgent: viewModel.selectedAgent,
                isSessionReady: viewModel.isSessionReady,
                isRestoringSession: viewModel.isResumingSession,
                audioService: viewModel.audioService,
                autocompleteHandler: viewModel.autocompleteHandler,
                onSend: { sendMessage() },
                onCancel: viewModel.cancelCurrentPrompt,
                onAutocompleteSelect: { handleAutocompleteSelection() },
                onImagePaste: { data, mimeType in
                    let maxImageSizeBytes = 10 * 1024 * 1024
                    guard data.count <= maxImageSizeBytes else {
                        let sizeText = ByteCountFormatter.string(
                            fromByteCount: Int64(data.count),
                            countStyle: .file
                        )
                        viewModel.currentAgentSession?.addSystemMessage(
                            "Pasted image is too large (\(sizeText)). Maximum size is 10MB."
                        )
                        return
                    }
                    viewModel.attachments.append(.image(data, mimeType: mimeType))
                },
                onFilePaste: { url in
                    viewModel.attachments.append(.file(url))
                },
                onAgentSelect: viewModel.requestAgentSwitch
            )
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .task(id: geometry.size.width) {
                            updateInputBarWidth(geometry.size.width)
                        }
                }
            }
            .padding(.horizontal, 20)

            ChatControlsBar(
                currentAgentSession: viewModel.currentAgentSession,
                hasModes: viewModel.hasModes,
                onShowUsage: { showingUsageSheet = true },
                onShowHistory: {
                    SessionsWindowController.shared.show(context: viewContext, worktreeId: worktree.id)
                },
                showsUsage: supportsUsageMetrics
            )
            .padding(.horizontal, 20)
        }
    }
}
