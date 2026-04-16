//
//  ModeSelectorView.swift
//  aizen
//
//  Session mode selector component
//

import ACP
import SwiftUI

struct ModeSelectorView: View {
    let availableModes: [ModeInfo]
    let currentModeId: String?
    let isStreaming: Bool
    var showsBackground: Bool = true
    let onSelectMode: (String) -> Void

    var body: some View {
        Menu {
            ForEach(availableModes, id: \.id) { modeInfo in
                Button {
                    onSelectMode(modeInfo.id)
                } label: {
                    HStack {
                        if let mode = SessionMode(rawValue: modeInfo.id) {
                            modeIcon(for: mode)
                        }
                        Text(modeInfo.name)
                        Spacer()
                        if modeInfo.id == currentModeId {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                if let currentModeId,
                   let mode = SessionMode(rawValue: currentModeId) {
                    modeIcon(for: mode)
                } else {
                    Image(systemName: "checklist")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                if let currentModeId,
                   let currentMode = availableModes.first(where: { $0.id == currentModeId }) {
                    Text(currentMode.name)
                        .font(.system(size: showsBackground ? 12 : 13, weight: .medium))
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: showsBackground ? 8 : 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, showsBackground ? 10 : 0)
            .padding(.vertical, showsBackground ? 5 : 0)
            .background {
                if showsBackground {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .disabled(isStreaming)  // Prevent mode changes during agent turn
        .opacity(isStreaming ? 0.5 : 1.0)
        .id(currentModeId)  // Force view update on mode change
    }

    private func modeIcon(for mode: SessionMode) -> some View {
        Group {
            switch mode {
            case .chat:
                Image(systemName: "message")
            case .code:
                Image(systemName: "chevron.left.forwardslash.chevron.right")
            case .ask:
                Image(systemName: "questionmark.circle")
            }
        }
        .font(.system(size: 13))
    }
}
