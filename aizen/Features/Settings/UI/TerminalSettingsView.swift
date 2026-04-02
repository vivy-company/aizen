//
//  TerminalSettingsView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI
import os.log

struct TerminalSettingsView: View {
    private let logger = Logger.settings
    @AppStorage("terminalNotificationsEnabled") private var terminalNotificationsEnabled = true
    @AppStorage("terminalProgressEnabled") private var terminalProgressEnabled = true
    @AppStorage("terminalVoiceButtonEnabled") private var terminalVoiceButtonEnabled = true
    @AppStorage("terminalSessionPersistence") private var sessionPersistence = false

    // Copy settings
    @AppStorage("terminalCopyTrimTrailingWhitespace") private var copyTrimTrailingWhitespace = true
    @AppStorage("terminalCopyCollapseBlankLines") private var copyCollapseBlankLines = false
    @AppStorage("terminalCopyStripShellPrompts") private var copyStripShellPrompts = false
    @AppStorage("terminalCopyFlattenCommands") private var copyFlattenCommands = false
    @AppStorage("terminalCopyRemoveBoxDrawing") private var copyRemoveBoxDrawing = false
    @AppStorage("terminalCopyStripAnsiCodes") private var copyStripAnsiCodes = true

    @StateObject private var presetManager = TerminalPresetStore.shared
    @State private var tmuxAvailable = false
    @State private var clearingTmuxSessions = false
    @State private var showingAddPreset = false
    @State private var editingPreset: TerminalPreset?

    var body: some View {
        Form {
            Section("Terminal Behavior") {
                Toggle("Enable terminal notifications", isOn: $terminalNotificationsEnabled)
                Toggle("Show progress overlays", isOn: $terminalProgressEnabled)
                Toggle("Show voice input button", isOn: $terminalVoiceButtonEnabled)
            }

            Section {
                Toggle("Trim trailing whitespace", isOn: $copyTrimTrailingWhitespace)
                Toggle("Collapse multiple blank lines", isOn: $copyCollapseBlankLines)
                Toggle("Strip shell prompts ($ #)", isOn: $copyStripShellPrompts)
                Toggle("Flatten multi-line commands", isOn: $copyFlattenCommands)
                Toggle("Remove box-drawing characters", isOn: $copyRemoveBoxDrawing)
                Toggle("Strip ANSI escape codes", isOn: $copyStripAnsiCodes)
            } header: {
                Text("Copy Text Processing")
            } footer: {
                Text("Transformations applied when copying text from terminal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Persist terminal sessions", isOn: $sessionPersistence)
                    .disabled(!tmuxAvailable)

                if sessionPersistence {
                    Text("Terminal sessions will survive app restarts using tmux")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        clearingTmuxSessions = true
                        Task {
                            await TmuxSessionRuntime.shared.killAllAizenSessions()
                            clearingTmuxSessions = false
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if clearingTmuxSessions {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text("Clear All Persistent Sessions")
                        }
                    }
                    .disabled(clearingTmuxSessions)
                }

                if !tmuxAvailable {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("tmux not installed. Install via: brew install tmux")
                            .font(.caption)
                    }
                }
            } header: {
                Text("Advanced")
            } footer: {
                if tmuxAvailable && !sessionPersistence {
                    Text("When enabled, terminals run inside hidden tmux sessions and preserve their state when the app is closed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                ForEach(presetManager.presets) { preset in
                    HStack(spacing: 12) {
                        Image(systemName: preset.icon)
                            .frame(width: 20)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.name)
                                .fontWeight(.medium)
                            Text(preset.command)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Button {
                            editingPreset = preset
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)

                        Button {
                            presetManager.deletePreset(id: preset.id)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                }
                .onMove { source, destination in
                    presetManager.movePreset(from: source, to: destination)
                }

                Button {
                    showingAddPreset = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color.accentColor)
                        Text("Add Preset")
                    }
                }
                .buttonStyle(.plain)
            } header: {
                Text("Terminal Presets")
            } footer: {
                Text("Presets appear in the empty terminal state and when long-pressing the + button")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .settingsSurface()
        .onAppear {
            tmuxAvailable = TmuxSessionRuntime.shared.isTmuxAvailable()
        }
        .sheet(isPresented: $showingAddPreset) {
            TerminalPresetFormView(
                onSave: { _ in },
                onCancel: {}
            )
        }
        .sheet(item: $editingPreset) { preset in
            TerminalPresetFormView(
                existingPreset: preset,
                onSave: { _ in },
                onCancel: {}
            )
        }
    }
}

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}
