import ACP
import CoreData
import SwiftUI
import VVChatTimeline

extension ChatSessionView {
    func toggleChatVoiceRecording() {
        if showingVoiceRecording {
            acceptChatVoiceRecording()
        } else {
            startChatVoiceRecording()
        }
    }

    func startChatVoiceRecording() {
        Task {
            do {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showingVoiceRecording = true
                }
                try await viewModel.audioService.startRecording()
            } catch {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showingVoiceRecording = false
                }
                if let recordingError = error as? AudioService.RecordingError {
                    permissionErrorMessage = recordingError.localizedDescription + "\n\nPlease enable Microphone and Speech Recognition permissions in System Settings."
                } else {
                    permissionErrorMessage = error.localizedDescription
                }
                showingPermissionError = true
            }
        }
    }

    func acceptChatVoiceRecording() {
        Task {
            let text = await viewModel.audioService.stopRecording()
            let finalText = text.isEmpty ? viewModel.audioService.partialTranscription : text
            await MainActor.run {
                if !finalText.isEmpty {
                    inputText = finalText
                }
                showingVoiceRecording = false
            }
        }
    }

    func cancelChatVoiceRecording() {
        viewModel.audioService.cancelRecording()
        showingVoiceRecording = false
    }
}
