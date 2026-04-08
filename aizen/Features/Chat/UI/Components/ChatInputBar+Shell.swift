//
//  ChatInputBar+Shell.swift
//  aizen
//

import SwiftUI

extension ChatInputBar {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            inputContent
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
        .overlay { composerBorder }
    }

    @ViewBuilder
    private var inputContent: some View {
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
                textEditorContent
            }
        }
    }

    @ViewBuilder
    private var textEditorContent: some View {
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

    @ViewBuilder
    private var composerBorder: some View {
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
