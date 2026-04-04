//
//  ChatInputBar+Support.swift
//  aizen
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import os.log

extension ChatInputBar {
    func handleAutocompleteNavigation(_ action: AutocompleteNavigationAction) -> Bool {
        guard autocompleteHandler.state.isActive else { return false }

        switch action {
        case .up:
            return autocompleteHandler.navigateUp()
        case .down:
            return autocompleteHandler.navigateDown()
        case .select:
            if autocompleteHandler.state.selectedItem != nil {
                onAutocompleteSelect()
                return true
            }
            return false
        case .dismiss:
            autocompleteHandler.dismissAutocomplete()
            return true
        }
    }

    func presentAttachmentPicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.item]

        if !worktreePath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: worktreePath)
        }

        panel.begin { response in
            if response == .OK {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    attachments.append(contentsOf: panel.urls.map { .file($0) })
                }
            }
        }
    }

    func startVoiceRecording() {
        Task {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                showingVoiceRecording = true
            }
            do {
                try await audioService.startRecording()
            } catch {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showingVoiceRecording = false
                }
                if let recordingError = error as? AudioService.RecordingError {
                    permissionErrorMessage = recordingError.localizedDescription
                        + "\n\nPlease enable Microphone and Speech Recognition permissions in System Settings."
                    showingPermissionError = true
                }
                logger.error("Failed to start recording: \(error.localizedDescription)")
            }
        }
    }

    var canSend: Bool {
        let hasText = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAttachments = !attachments.isEmpty
        return (hasText || hasAttachments) && !isProcessing && isSessionReady
    }

    var inputCornerRadius: CGFloat {
        if showingVoiceRecording {
            return Layout.cornerRadiusVoice
        }
        return Layout.cornerRadiusNormal
    }

    var textEditorHeight: CGFloat {
        let measured = measuredTextHeight > 0 ? measuredTextHeight : Layout.textMinHeight
        return min(max(measured, Layout.textMinHeight), Layout.textMaxHeight)
    }

    var shouldAnimateBorder: Bool {
        !disableAnimatedBordersForPerfProbe && scenePhase == .active && isTextEditorFocused
    }
}
