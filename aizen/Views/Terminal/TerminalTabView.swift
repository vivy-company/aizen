//
//  TerminalTabView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import ACP
import os.log
import SwiftUI

struct TerminalTabView: View {
    @ObservedObject var worktree: Worktree
    @Binding var selectedSessionId: UUID?
    @ObservedObject var repositoryManager: RepositoryManager

    private let sessionManager = TerminalSessionManager.shared
    @StateObject private var presetManager = TerminalPresetManager.shared
    private let logger = Logger.terminal

    var sessions: [TerminalSession] {
        let sessions = (worktree.terminalSessions as? Set<TerminalSession>) ?? []
        return sessions
            .filter { !$0.isDeleted }
            .sorted { ($0.createdAt ?? Date()) < ($1.createdAt ?? Date()) }
    }

    // Derive valid selection declaratively
    private var validatedSelectedSessionId: UUID? {
        // If current selection is valid, use it
        if let currentId = selectedSessionId,
           sessions.contains(where: { $0.id == currentId }) {
            return currentId
        }
        // Otherwise, select first or last session if available
        return sessions.last?.id ?? sessions.first?.id
    }

    var body: some View {
        if sessions.isEmpty {
            terminalEmptyState
        } else {
            ZStack {
                // Keep all terminal views alive to avoid recreation on tab switch
                // Use opacity + allowsHitTesting instead of conditional rendering
                ForEach(sessions) { session in
                    let isSelected = validatedSelectedSessionId == session.id
                    SplitTerminalView(
                        worktree: worktree,
                        session: session,
                        sessionManager: sessionManager,
                        isSelected: isSelected
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(isSelected ? 1 : 0)
                    .animation(nil, value: isSelected)
                    .allowsHitTesting(isSelected)
                    .zIndex(isSelected ? 1 : 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task {
                // Sync binding once with validated value
                if selectedSessionId != validatedSelectedSessionId {
                    selectedSessionId = validatedSelectedSessionId
                }
            }
        }
    }

    private var terminalEmptyState: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    Text("terminal.noSessions", bundle: .main)
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("terminal.openInWorktree", bundle: .main)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }

            // New terminal button
            Button {
                createNewSession()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text("terminal.new", bundle: .main)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.blue, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            // Presets section
            if !presetManager.presets.isEmpty {
                VStack(spacing: 16) {
                    Text("Or launch a preset")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        ForEach(presetManager.presets.prefix(5)) { preset in
                            Button {
                                createNewSession(withPreset: preset)
                            } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: preset.icon)
                                        .font(.system(size: 24))
                                    Text(preset.name)
                                        .font(.system(size: 13, weight: .medium))
                                        .lineLimit(1)
                                }
                                .frame(width: 100, height: 80)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(.separator.opacity(0.3), lineWidth: 1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func createNewSession(withPreset preset: TerminalPreset? = nil) {
        guard let context = worktree.managedObjectContext else { return }

        let session = TerminalSession(context: context)
        session.id = UUID()
        session.createdAt = Date()
        session.worktree = worktree

        if let preset = preset {
            session.title = preset.name
            session.initialCommand = preset.command
            logger.info("Creating session with preset: \(preset.name), command: \(preset.command)")
        } else {
            session.title = String(localized: "worktree.session.terminalTitle", defaultValue: "Terminal \(sessions.count + 1)", bundle: .main)
        }

        do {
            try context.save()
            logger.info("Session saved, initialCommand: \(session.initialCommand ?? "nil")")
            selectedSessionId = session.id
        } catch {
            logger.error("Failed to create terminal session: \(error.localizedDescription)")
        }
    }
}

#Preview {
    TerminalTabView(
        worktree: Worktree(),
        selectedSessionId: .constant(nil),
        repositoryManager: RepositoryManager(viewContext: PersistenceController.preview.container.viewContext)
    )
}
