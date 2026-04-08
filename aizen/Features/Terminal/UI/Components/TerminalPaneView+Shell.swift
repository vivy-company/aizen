import SwiftUI

extension TerminalPaneView {
    var body: some View {
        Group {
            if let surfaceView {
                AizenInspectableSurface(
                    surfaceView: surfaceView,
                    adapter: surfaceAdapter,
                    effectiveThemeName: effectiveThemeName,
                    isSplit: isSplit,
                    isFocused: isFocused,
                    showsProgress: progressEnabled
                )
                .overlay(alignment: .bottom) {
                    if showingVoiceRecording {
                        voiceOverlay
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if !showingVoiceRecording && isFocused && voiceButtonEnabled {
                        voiceTriggerButton
                            .transition(.opacity)
                    }
                }
            } else {
                Color.clear
                    .onAppear {
                        resolveSurfaceIfNeeded()
                    }
            }
        }
        .onAppear {
            resolveSurfaceIfNeeded()
            surfaceView?.setGhosttyFocused(isFocused)
            if isFocused {
                requestSurfaceFocus()
            }
        }
        .task(id: isFocused) {
            surfaceView?.setGhosttyFocused(isFocused)
            if isFocused {
                requestSurfaceFocus()
            }
            if !isFocused, showingVoiceRecording {
                audioService.cancelRecording()
                setVoiceRecording(false)
            }
        }
        .task(id: focusRequestVersion) {
            if isFocused {
                requestSurfaceFocus()
            }
        }
        .onDisappear {
            if showingVoiceRecording {
                audioService.cancelRecording()
                setVoiceRecording(false)
            }
        }
        .task(id: voiceAction) {
            guard let action = voiceAction else { return }
            handleVoiceAction(action)
            voiceAction = nil
        }
        .alert("Voice Input Unavailable", isPresented: $showingPermissionError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(permissionErrorMessage)
        }
    }
}
