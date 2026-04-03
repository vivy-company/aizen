import SwiftUI

extension TerminalPaneView {
    var voiceOverlay: some View {
        VoiceRecordingView(
            audioService: audioService,
            onSend: { transcribedText in
                sendTranscriptionToTerminal(transcribedText)
                setVoiceRecording(false)
            },
            onCancel: {
                setVoiceRecording(false)
            }
        )
        .padding(12)
        .frame(maxWidth: 520)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .padding(16)
    }

    var voiceTriggerButton: some View {
        Button {
            startVoiceRecording()
        } label: {
            Image(systemName: "mic.fill")
                .font(.system(size: 16, weight: .semibold))
                .padding(10)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .help("Voice input (⌘⇧M)")
        .padding(14)
    }

    func handleVoiceAction(_ action: VoiceAction) {
        switch action {
        case .toggle:
            toggleVoiceRecording()
        case .cancel:
            audioService.cancelRecording()
            setVoiceRecording(false)
        case .accept:
            toggleVoiceRecording()
        }
    }

    func toggleVoiceRecording() {
        if showingVoiceRecording {
            Task {
                let text = await audioService.stopRecording()
                await MainActor.run {
                    let fallback = text.isEmpty ? audioService.partialTranscription : text
                    sendTranscriptionToTerminal(fallback)
                    setVoiceRecording(false)
                }
            }
        } else {
            startVoiceRecording()
        }
    }

    func startVoiceRecording() {
        Task {
            do {
                setVoiceRecording(true)
                try await audioService.startRecording()
            } catch {
                setVoiceRecording(false)
                if let recordingError = error as? AudioService.RecordingError {
                    permissionErrorMessage = recordingError.localizedDescription + "\n\nEnable Microphone and Speech Recognition in System Settings."
                } else {
                    permissionErrorMessage = error.localizedDescription
                }
                showingPermissionError = true
            }
        }
    }

    func sendTranscriptionToTerminal(_ text: String) {
        let trimmed = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        surfaceAdapter.sendText(trimmed)
    }

    func setVoiceRecording(_ isRecording: Bool) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showingVoiceRecording = isRecording
        }
        onVoiceRecordingChanged(isRecording)
    }
}
