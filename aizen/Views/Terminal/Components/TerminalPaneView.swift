//
//  TerminalPaneView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI
import AppKit

// MARK: - Terminal Pane View

struct TerminalPaneView: View {
    @ObservedObject var worktree: Worktree
    @ObservedObject var session: TerminalSession
    let paneId: String
    let isFocused: Bool
    let sessionManager: TerminalSessionManager
    let onFocus: () -> Void
    let onProcessExit: () -> Void
    let onTitleChange: (String) -> Void

    @State private var shouldFocus: Bool = false
    @State private var focusVersion: Int = 0  // Increment to force updateNSView
    @State private var isLoading: Bool = false
    @State private var progressState: GhosttyProgressState = .remove
    @State private var progressValue: Int? = nil
    @State private var isResizing: Bool = false
    @State private var terminalColumns: UInt16 = 0
    @State private var terminalRows: UInt16 = 0
    @State private var hideWorkItem: DispatchWorkItem?
    @StateObject private var audioService = AudioService()
    @State private var showingVoiceRecording = false
    @State private var showingPermissionError = false
    @State private var permissionErrorMessage = ""
    @State private var keyMonitor: Any?

    @AppStorage("terminalNotificationsEnabled") private var notificationsEnabled = true
    @AppStorage("terminalProgressEnabled") private var progressEnabled = true
    @AppStorage("terminalVoiceButtonEnabled") private var voiceButtonEnabled = true

    var body: some View {
        GeometryReader { geo in
            ZStack {
                TerminalViewWrapper(
                    worktree: worktree,
                    session: session,
                    paneId: paneId,
                    sessionManager: sessionManager,
                    onProcessExit: {
                        if notificationsEnabled && (!isFocused || !NSApp.isActive) {
                            TerminalNotificationManager.shared.notify(
                                title: "Terminal exited",
                                body: session.title ?? "Shell process ended"
                            )
                        }
                        onProcessExit()
                    },
                    onReady: { },
                    onTitleChange: onTitleChange,
                    onProgress: { state, value in
                        progressState = state
                        progressValue = value
                        if state == .remove {
                            isLoading = false
                        }
                    },
                    shouldFocus: shouldFocus,  // Pass value directly, not binding
                    isFocused: isFocused,      // Pass focused state to manage resignation
                    focusVersion: focusVersion, // Version counter to force updateNSView
                    size: geo.size
                )

                if progressEnabled && progressState != .remove && progressState != .unknown {
                    progressOverlay
                        .transition(.opacity)
                        .padding(.horizontal, 0)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }

                if isResizing {
                    ResizeOverlay(columns: terminalColumns, rows: terminalRows)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                        .animation(.easeOut(duration: 0.1), value: isResizing)
                }

                if showingVoiceRecording {
                    voiceOverlay
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if isFocused && voiceButtonEnabled {
                    voiceTriggerButton
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .transition(.opacity)
                }
            }
            .onChange(of: geo.size) { _ in
                handleSizeChange()
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .opacity(isFocused ? 1.0 : 0.6)
        .clipped()
        .animation(nil, value: isFocused)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isFocused {
                        onFocus()
                    }
                }
        )
        .onChange(of: isFocused) { newValue in
            if newValue {
                shouldFocus = true
                focusVersion += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    shouldFocus = false
                }
            } else {
                focusVersion += 1
                if showingVoiceRecording {
                    audioService.cancelRecording()
                    showingVoiceRecording = false
                }
            }
        }
        .onAppear {
            if isFocused {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    shouldFocus = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        shouldFocus = false
                    }
                }
            }
            if keyMonitor == nil {
                keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    handleVoiceShortcut(event)
                }
            }
        }
        .onDisappear {
            hideWorkItem?.cancel()
            hideWorkItem = nil
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
            if showingVoiceRecording {
                audioService.cancelRecording()
                showingVoiceRecording = false
            }
        }
        .alert("Voice Input Unavailable", isPresented: $showingPermissionError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(permissionErrorMessage)
        }
    }

    private func handleSizeChange() {
        guard let sessionId = session.id,
              let terminal = sessionManager.getTerminal(for: sessionId, paneId: paneId),
              let termSize = terminal.terminalSize() else { return }

        terminalColumns = termSize.columns
        terminalRows = termSize.rows

        isResizing = true

        hideWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            isResizing = false
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    private var progressOverlay: some View {
        ZStack(alignment: .topLeading) {
            // Background track
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 2)
            // Determinate bar
            if progressState == .set, let value = progressValue {
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: geo.size.width * CGFloat(value) / 100.0, height: 2)
                        .animation(.easeOut(duration: 0.12), value: value)
                }
                .frame(height: 2)
            } else if progressState == .indeterminate || progressState == .pause || progressState == .error {
                // Indeterminate "ping-pong" bar
                IndeterminateBar(color: progressState == .error ? .red : .accentColor)
                    .frame(height: 2)
            }
        }
        .padding(.horizontal, 0.5)
    }

    private var voiceOverlay: some View {
        VoiceRecordingView(
            audioService: audioService,
            onSend: { transcribedText in
                sendTranscriptionToTerminal(transcribedText)
                showingVoiceRecording = false
            },
            onCancel: {
                showingVoiceRecording = false
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

    private var voiceTriggerButton: some View {
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

    private func handleVoiceShortcut(_ event: NSEvent) -> NSEvent? {
        guard isFocused else { return event }
        let keyCodeEscape: UInt16 = 53
        let keyCodeReturn: UInt16 = 36

        if showingVoiceRecording {
            if event.keyCode == keyCodeEscape {
                audioService.cancelRecording()
                showingVoiceRecording = false
                return nil
            }
            if event.keyCode == keyCodeReturn {
                toggleVoiceRecording()
                return nil
            }
        }

        guard event.modifierFlags.contains(.command),
              event.modifierFlags.contains(.shift),
              event.charactersIgnoringModifiers?.lowercased() == "m" else {
            return event
        }
        toggleVoiceRecording()
        return nil
    }

    private func toggleVoiceRecording() {
        if showingVoiceRecording {
            Task {
                let text = await audioService.stopRecording()
                await MainActor.run {
                    let fallback = text.isEmpty ? audioService.partialTranscription : text
                    sendTranscriptionToTerminal(fallback)
                    showingVoiceRecording = false
                }
            }
        } else {
            startVoiceRecording()
        }
    }

    private func startVoiceRecording() {
        Task {
            do {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showingVoiceRecording = true
                }
                try await audioService.startRecording()
            } catch {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showingVoiceRecording = false
                }
                if let recordingError = error as? AudioService.RecordingError {
                    permissionErrorMessage = recordingError.localizedDescription + "\n\nEnable Microphone and Speech Recognition in System Settings."
                } else {
                    permissionErrorMessage = error.localizedDescription
                }
                showingPermissionError = true
            }
        }
    }

    private func sendTranscriptionToTerminal(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let sessionId = session.id,
              let terminal = sessionManager.getTerminal(for: sessionId, paneId: paneId) else {
            return
        }
        terminal.surface?.sendText(trimmed)
    }
}
