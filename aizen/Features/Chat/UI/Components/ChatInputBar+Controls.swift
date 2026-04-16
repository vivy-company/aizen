//
//  ChatInputBar+Controls.swift
//  aizen
//

import SwiftUI

extension ChatInputBar {
    @ViewBuilder
    var controlsRow: some View {
        HStack(spacing: Layout.rowSpacing) {
            attachmentButton

            if !availableModels.isEmpty {
                ModelSelectorMenu(
                    availableModels: availableModels,
                    currentModelId: currentModelId,
                    isStreaming: isSessionStreaming,
                    selectedAgent: selectedAgent,
                    onModelSelect: onModelSelect,
                    onAgentSelect: onAgentSelect,
                    showsBackground: false
                )
                .transition(.opacity)
            }

            if currentModeId == "plan" {
                Label("Plan", systemImage: "checklist")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.blue)
            }

            Spacer(minLength: Layout.rowSpacing)

            trailingControls
                .frame(height: Layout.controlSize)
        }
    }

    private var attachmentButton: some View {
        Button(action: presentAttachmentPicker) {
            Image(systemName: "paperclip")
                .font(.system(size: Layout.iconSize, weight: .medium))
                .foregroundStyle(!isSessionReady ? .tertiary : .secondary)
                .frame(width: Layout.attachmentControlSize, height: Layout.attachmentControlSize)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isSessionReady)
        .transition(.opacity)
    }

    private var trailingControls: some View {
        HStack(spacing: Layout.rowSpacing) {
            Button(action: startVoiceRecording) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(!isSessionReady ? .tertiary : .secondary)
                    .frame(width: Layout.controlSize, height: Layout.controlSize)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!isSessionReady)
            .transition(.opacity)

            if isProcessing {
                Button(action: onCancel) {
                    ZStack {
                        Circle()
                            .fill(Color.white)
                        Image(systemName: "stop.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.9))
                    }
                    .frame(width: Layout.controlSize, height: Layout.controlSize)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            } else {
                Button(action: onSend) {
                    ZStack {
                        Circle()
                            .fill(canSend ? Color.white : Color.white.opacity(0.3))
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(canSend ? Color.black.opacity(0.9) : Color.secondary)
                    }
                    .frame(width: Layout.controlSize, height: Layout.controlSize)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: canSend)
                .transition(.opacity)
            }
        }
    }
}
