//
//  ChatInputBar.swift
//  aizen
//
//  Chat input bar with attachments, voice, and model selection
//

import SwiftUI
import UniformTypeIdentifiers
import os.log

struct ChatInputBar: View {
    private let logger = Logger.chat
    @Binding var inputText: String
    @Binding var pendingCursorPosition: Int?
    @Binding var attachments: [ChatAttachment]
    @Binding var isProcessing: Bool
    @Binding var showingVoiceRecording: Bool
    @Binding var showingAttachmentPicker: Bool
    @Binding var showingPermissionError: Bool
    @Binding var permissionErrorMessage: String

    let session: AgentSession?
    let currentModeId: String?
    let selectedAgent: String
    let isSessionReady: Bool
    let audioService: AudioService
    @ObservedObject var autocompleteHandler: UnifiedAutocompleteHandler

    let onSend: () -> Void
    let onCancel: () -> Void
    let onAutocompleteSelect: () -> Void

    @State private var isHoveringInput = false
    @State private var dashPhase: CGFloat = 0
    @State private var gradientRotation: Double = 0

    private let gradientColors: [Color] = [
        .accentColor.opacity(0.7), .accentColor.opacity(0.4), .accentColor.opacity(0.7)
    ]

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if !showingVoiceRecording {
                Button(action: { showingAttachmentPicker.toggle() }) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(!isSessionReady ? .tertiary : .secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!isSessionReady)
                .transition(.opacity)
            }

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
                        Text(isSessionReady ? String(localized: "chat.input.placeholder") : String(localized: "chat.session.starting"))
                            .font(.system(size: 14))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 6)
                            .allowsHitTesting(false)
                    }

                    CustomTextEditor(
                        text: $inputText,
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
                        pendingCursorPosition: $pendingCursorPosition
                    )
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .frame(height: textEditorHeight)
                    .disabled(!isSessionReady)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 40)

            if !showingVoiceRecording {
                if let agentSession = session, !agentSession.availableModels.isEmpty {
                    ModelSelectorMenu(session: agentSession, selectedAgent: selectedAgent)
                        .transition(.opacity)
                }

                Button(action: {
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
                                permissionErrorMessage = recordingError.localizedDescription + "\n\nPlease enable Microphone and Speech Recognition permissions in System Settings."
                                showingPermissionError = true
                            }
                            logger.error("Failed to start recording: \(error.localizedDescription)")
                        }
                    }
                }) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(!isSessionReady ? .tertiary : .secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!isSessionReady)
                .help(String(localized: "chat.voice.record"))
                .transition(.opacity)

                if isProcessing {
                    Button(action: onCancel) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Color.red)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                } else {
                    Button(action: onSend) {
                        Image(systemName: canSend ? "arrow.up.circle.fill" : "arrow.up.circle")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(canSend ? Color.blue : Color.secondary.opacity(0.5))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: canSend)
                    .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: inputCornerRadius, style: .continuous))
        .overlay {
            if isProcessing {
                RoundedRectangle(cornerRadius: inputCornerRadius, style: .continuous)
                    .strokeBorder(
                        AngularGradient(
                            colors: gradientColors,
                            center: .center,
                            angle: .degrees(gradientRotation)
                        ),
                        lineWidth: 2
                    )
            } else if currentModeId != "plan" {
                RoundedRectangle(cornerRadius: inputCornerRadius, style: .continuous)
                    .strokeBorder(.separator.opacity(isHoveringInput ? 0.5 : 0.2), lineWidth: 0.5)
            }

            if currentModeId == "plan" && !isProcessing {
                RoundedRectangle(cornerRadius: inputCornerRadius, style: .continuous)
                    .stroke(
                        AngularGradient(
                            colors: gradientColors,
                            center: .center,
                            angle: .degrees(gradientRotation)
                        ),
                        style: StrokeStyle(lineWidth: 2, dash: [8])
                    )
            }
        }
        .onChange(of: isProcessing) { newValue in
            if newValue {
                startGradientAnimation()
            }
        }
        .onChange(of: currentModeId) { newMode in
            if newMode == "plan" {
                startGradientAnimation()
            }
        }
        .onAppear {
            if currentModeId == "plan" {
                startGradientAnimation()
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHoveringInput = hovering
            }
        }
        .fileImporter(
            isPresented: $showingAttachmentPicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    attachments.append(contentsOf: urls.map { .file($0) })
                }
            }
        }
    }

    private func handleAutocompleteNavigation(_ action: AutocompleteNavigationAction) -> Bool {
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

    private var canSend: Bool {
        let hasText = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAttachments = !attachments.isEmpty
        return (hasText || hasAttachments) && !isProcessing && isSessionReady
    }

    private var inputCornerRadius: CGFloat {
        if showingVoiceRecording {
            return 28
        }
        let lineCount = inputText.components(separatedBy: .newlines).count
        return lineCount > 1 ? 20 : 28
    }

    private var textEditorHeight: CGFloat {
        let lineCount = max(1, inputText.components(separatedBy: .newlines).count)
        let lineHeight: CGFloat = 18
        let baseHeight: CGFloat = lineHeight + 12
        return min(max(baseHeight, CGFloat(lineCount) * lineHeight + 12), 120)
    }

    private func startGradientAnimation() {
        withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
            gradientRotation = 360
        }
    }
}
