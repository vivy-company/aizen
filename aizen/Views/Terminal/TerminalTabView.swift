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
    @Environment(\.colorScheme) private var colorScheme

    private let sessionManager = TerminalSessionManager.shared
    @StateObject private var presetManager = TerminalPresetManager.shared
    private let logger = Logger.terminal
    private let visiblePresetsLimit = 8
    private let emptyStateMaxWidth: CGFloat = 540

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
        let visiblePresets = Array(presetManager.presets.prefix(visiblePresetsLimit))

        return VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 24) {
                terminalHeader
                newTerminalButton

                if !visiblePresets.isEmpty {
                    launchPresetSeparator
                    presetButtons(for: visiblePresets)
                }
            }
            .frame(maxWidth: emptyStateMaxWidth)
            .padding(.horizontal, 24)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var terminalHeader: some View {
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
    }

    @ViewBuilder
    private var newTerminalButton: some View {
        if #available(macOS 26.0, *) {
            Button {
                createNewSession()
            } label: {
                Label("terminal.new", systemImage: "plus.circle.fill")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        } else {
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
                .background(.blue, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
    }

    private var launchPresetSeparator: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 1)
            Text("Or launch a preset")
                .font(.caption)
                .foregroundStyle(.secondary)
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 1)
        }
        .frame(maxWidth: 460)
    }

    @ViewBuilder
    private func presetButtons(for presets: [TerminalPreset]) -> some View {
        VStack(spacing: 8) {
            ForEach(presets) { preset in
                presetButton(for: preset)
            }
        }
        .frame(maxWidth: 460)
    }

    private func presetButton(for preset: TerminalPreset) -> some View {
        let trimmedCommand = preset.command.trimmingCharacters(in: .whitespacesAndNewlines)

        return Button {
            createNewSession(withPreset: preset)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: preset.icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 24, height: 24)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if !trimmedCommand.isEmpty {
                        Text(trimmedCommand)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                emptyStateItemBackground(cornerRadius: 12)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(emptyStateItemStrokeColor, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func emptyStateItemBackground(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            shape
                .fill(.white.opacity(0.001))
                .glassEffect(.regular.interactive(), in: shape)
        } else {
            shape.fill(.thinMaterial)
        }
    }

    private var emptyStateItemStrokeColor: Color {
        colorScheme == .dark ? .white.opacity(0.10) : .black.opacity(0.08)
    }

    private func createNewSession(withPreset preset: TerminalPreset? = nil) {
        guard let context = worktree.managedObjectContext else { return }

        let session = TerminalSession(context: context)
        session.id = UUID()
        session.createdAt = Date()
        session.worktree = worktree
        let defaultPaneId = TerminalLayoutDefaults.paneId(sessionId: session.id, focusedPaneId: nil)
        session.focusedPaneId = defaultPaneId
        session.splitLayout = SplitLayoutHelper.encode(TerminalLayoutDefaults.defaultLayout(paneId: defaultPaneId))

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
