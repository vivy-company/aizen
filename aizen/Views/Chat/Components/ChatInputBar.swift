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
    private let logger = Logger.chat
    @Binding var inputText: String
    @Binding var pendingCursorPosition: Int?
    @Binding var attachments: [ChatAttachment]
    @Binding var isProcessing: Bool
    @Binding var showingVoiceRecording: Bool
    @Binding var showingAttachmentPicker: Bool
    @Binding var showingPermissionError: Bool
    @Binding var permissionErrorMessage: String

    let worktreePath: String
    let session: AgentSession?
    let currentModeId: String?
    let selectedAgent: String
    let isSessionReady: Bool
    let audioService: AudioService
    @ObservedObject var autocompleteHandler: UnifiedAutocompleteHandler

    let onSend: () -> Void
    let onCancel: () -> Void
    let onAutocompleteSelect: () -> Void
    let onImagePaste: (Data, String) -> Void
    let onAgentSelect: (String) -> Void

    @State private var isHoveringInput = false
    @State private var measuredTextHeight: CGFloat = 0
    @State private var isTextEditorFocused = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    private let disableAnimatedBordersForPerfProbe = false

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
                        measuredHeight: $measuredTextHeight,
                        isFocused: $isTextEditorFocused,
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
            .frame(maxWidth: .infinity, minHeight: 40)

            if !showingVoiceRecording {
                if let agentSession = session, !agentSession.availableModels.isEmpty {
                    ModelSelectorMenu(session: agentSession, selectedAgent: selectedAgent, onAgentSelect: onAgentSelect)
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
                AnimatedGradientBorder(
                    cornerRadius: inputCornerRadius,
                    colors: gradientColors,
                    dashed: false,
                    reduceMotion: reduceMotion,
                    isActive: shouldAnimateBorder
                )
                .allowsHitTesting(false)
            } else if currentModeId != "plan" {
                RoundedRectangle(cornerRadius: inputCornerRadius, style: .continuous)
                    .strokeBorder(.separator.opacity(isHoveringInput ? 0.5 : 0.2), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }

            if currentModeId == "plan" && !isProcessing {
                AnimatedGradientBorder(
                    cornerRadius: inputCornerRadius,
                    colors: gradientColors,
                    dashed: true,
                    reduceMotion: reduceMotion,
                    isActive: shouldAnimateBorder
                )
                .allowsHitTesting(false)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHoveringInput = hovering
            }
        }
        .onChange(of: showingAttachmentPicker) { _, isShowing in
            guard isShowing else { return }
            showingAttachmentPicker = false

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
        let minHeight: CGFloat = 30
        let maxHeight: CGFloat = 120
        let measured = measuredTextHeight > 0 ? measuredTextHeight : minHeight
        return min(max(measured, minHeight), maxHeight)
    }

    private var shouldAnimateBorder: Bool {
        !disableAnimatedBordersForPerfProbe && scenePhase == .active && isTextEditorFocused
    }

}

private struct AnimatedGradientBorder: NSViewRepresentable {
    let cornerRadius: CGFloat
    let colors: [Color]
    let dashed: Bool
    let reduceMotion: Bool
    let isActive: Bool
    private let lineWidth: CGFloat = 2
    private let cycleSeconds: TimeInterval = 10

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> GradientBorderView {
        let view = GradientBorderView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: GradientBorderView, context: Context) {
        context.coordinator.update(
            in: nsView,
            cornerRadius: cornerRadius,
            colors: colors,
            dashed: dashed,
            reduceMotion: reduceMotion,
            isActive: isActive,
            lineWidth: lineWidth,
            cycleSeconds: cycleSeconds
        )
    }

    final class Coordinator {
        private let containerLayer = CALayer()
        private let gradientLayer = CAGradientLayer()
        private let maskLayer = CAShapeLayer()
        private var isAnimating = false
        private var currentCornerRadius: CGFloat = 0
        private var currentLineWidth: CGFloat = 0
        private weak var hostView: GradientBorderView?
        private let pulseKey = "aizen.gradientBorder.pulse"

        func attach(to view: GradientBorderView) {
            guard hostView == nil else { return }
            hostView = view
            view.wantsLayer = true
            view.layer = CALayer()
            view.layer?.masksToBounds = false
            view.layer?.addSublayer(containerLayer)
            containerLayer.masksToBounds = false
            containerLayer.addSublayer(gradientLayer)
            containerLayer.mask = maskLayer
            gradientLayer.type = .conic
            gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
            gradientLayer.endPoint = CGPoint(x: 1, y: 1)
            maskLayer.fillColor = nil
            maskLayer.strokeColor = NSColor.white.cgColor
            maskLayer.lineCap = .round
            view.layoutHandler = { [weak self] bounds in
                self?.layout(in: bounds)
            }
        }

        func update(
            in view: GradientBorderView,
            cornerRadius: CGFloat,
            colors: [Color],
            dashed: Bool,
            reduceMotion: Bool,
            isActive: Bool,
            lineWidth: CGFloat,
            cycleSeconds: TimeInterval
        ) {
            if hostView == nil {
                attach(to: view)
            }

            currentCornerRadius = cornerRadius
            currentLineWidth = lineWidth

            let nsColors = colors.map { NSColor($0).cgColor }
            gradientLayer.colors = nsColors + [nsColors.first].compactMap { $0 }
            maskLayer.lineWidth = lineWidth
            maskLayer.lineDashPattern = dashed ? [6, 6] : nil

            if let scale = view.window?.backingScaleFactor {
                view.layer?.contentsScale = scale
                containerLayer.contentsScale = scale
                gradientLayer.contentsScale = scale
                maskLayer.contentsScale = scale
            }

            layout(in: view.bounds)
            updateAnimation(reduceMotion: reduceMotion, isActive: isActive, cycleSeconds: cycleSeconds)
        }

        private func layout(in bounds: CGRect) {
            guard !bounds.isEmpty else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            containerLayer.frame = bounds
            gradientLayer.frame = bounds
            maskLayer.frame = bounds
            let inset = max(currentLineWidth / 2, 0.5)
            let rect = bounds.insetBy(dx: inset, dy: inset)
            maskLayer.path = CGPath(
                roundedRect: rect,
                cornerWidth: currentCornerRadius,
                cornerHeight: currentCornerRadius,
                transform: nil
            )
            CATransaction.commit()
        }

        private func updateAnimation(reduceMotion: Bool, isActive: Bool, cycleSeconds: TimeInterval) {
            if reduceMotion || !isActive {
                if isAnimating {
                    gradientLayer.removeAnimation(forKey: pulseKey)
                    isAnimating = false
                }
                gradientLayer.opacity = 1
                return
            }

            guard !isAnimating else { return }
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 0.55
            pulse.toValue = 1.0
            pulse.duration = cycleSeconds
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.isRemovedOnCompletion = false
            gradientLayer.add(pulse, forKey: pulseKey)
            isAnimating = true
        }
    }
}

private final class GradientBorderView: NSView {
    var layoutHandler: ((CGRect) -> Void)?

    override func layout() {
        super.layout()
        layoutHandler?(bounds)
    }
}
