//
//  ModeSelectorView.swift
//  aizen
//
//  Session mode selector component
//

import ACP
import SwiftUI

struct ModeSelectorView: View {
    @ObservedObject var session: AgentSession

    var body: some View {
        Menu {
            ForEach(session.availableModes, id: \.id) { modeInfo in
                Button {
                    Task {
                        try? await session.setModeById(modeInfo.id)
                    }
                } label: {
                    HStack {
                        if let mode = SessionMode(rawValue: modeInfo.id) {
                            modeIcon(for: mode)
                        }
                        Text(modeInfo.name)
                        Spacer()
                        if modeInfo.id == session.currentModeId {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                if let currentModeId = session.currentModeId,
                   let mode = SessionMode(rawValue: currentModeId) {
                    modeIcon(for: mode)
                }
                if let currentModeId = session.currentModeId,
                   let currentMode = session.availableModes.first(where: { $0.id == currentModeId }) {
                    Text(currentMode.name)
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .disabled(session.isStreaming)  // Prevent mode changes during agent turn
        .opacity(session.isStreaming ? 0.5 : 1.0)
        .id(session.currentModeId)  // Force view update on mode change
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
