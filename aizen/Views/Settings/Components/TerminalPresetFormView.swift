//
//  TerminalPresetFormView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 10.12.25.
//

import SwiftUI

struct TerminalPresetFormView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var command: String
    @State private var selectedIcon: String
    @State private var showingIconPicker = false

    let existingPreset: TerminalPreset?
    let onSave: (TerminalPreset) -> Void
    let onCancel: () -> Void

    private let commonIcons = [
        "terminal", "terminal.fill", "apple.terminal", "apple.terminal.fill",
        "chevron.left.forwardslash.chevron.right", "curlybraces",
        "brain", "brain.head.profile", "sparkles",
        "command", "option", "control",
        "gear", "wrench.and.screwdriver", "hammer",
        "play", "play.fill", "bolt", "bolt.fill",
        "arrow.trianglehead.2.clockwise", "arrow.clockwise",
        "doc.text", "folder", "server.rack"
    ]

    init(
        existingPreset: TerminalPreset? = nil,
        onSave: @escaping (TerminalPreset) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.existingPreset = existingPreset
        self.onSave = onSave
        self.onCancel = onCancel

        if let preset = existingPreset {
            _name = State(initialValue: preset.name)
            _command = State(initialValue: preset.command)
            _selectedIcon = State(initialValue: preset.icon)
        } else {
            _name = State(initialValue: "")
            _command = State(initialValue: "")
            _selectedIcon = State(initialValue: "terminal")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(existingPreset == nil ? "Add Terminal Preset" : "Edit Preset")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    dismiss()
                    onCancel()
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Form
            Form {
                Section("Basic Information") {
                    TextField("Name", text: $name)
                        .help("Display name for the preset (e.g., Claude, Helix, Vim)")

                    TextField("Command", text: $command, axis: .vertical)
                        .lineLimit(2...4)
                        .help("Command to run when preset is selected (e.g., claude, hx, nvim)")
                }

                Section("Icon") {
                    HStack(spacing: 12) {
                        Image(systemName: selectedIcon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 32, height: 32)

                        Text(selectedIcon)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        Button("Choose Symbol...") {
                            showingIconPicker = true
                        }
                        .buttonStyle(.bordered)
                    }

                    // Quick icon selection
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(36)), count: 8), spacing: 8) {
                        ForEach(commonIcons, id: \.self) { icon in
                            Button {
                                selectedIcon = icon
                            } label: {
                                Image(systemName: icon)
                                    .font(.system(size: 16))
                                    .frame(width: 32, height: 32)
                                    .background(
                                        selectedIcon == icon ?
                                        Color.accentColor.opacity(0.2) :
                                        Color(NSColor.controlBackgroundColor),
                                        in: RoundedRectangle(cornerRadius: 6)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()

            // Footer
            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button(existingPreset == nil ? "Add" : "Save") {
                    savePreset()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 450, height: 480)
        .sheet(isPresented: $showingIconPicker) {
            SFSymbolPickerView(selectedSymbol: $selectedIcon, isPresented: $showingIconPicker)
        }
    }

    private var isValid: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedCommand = command.trimmingCharacters(in: .whitespaces)
        return !trimmedName.isEmpty && !trimmedCommand.isEmpty
    }

    private func savePreset() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedCommand = command.trimmingCharacters(in: .whitespaces)

        if let existing = existingPreset {
            var updated = existing
            updated.name = trimmedName
            updated.command = trimmedCommand
            updated.icon = selectedIcon
            TerminalPresetManager.shared.updatePreset(updated)
            onSave(updated)
        } else {
            TerminalPresetManager.shared.addPreset(
                name: trimmedName,
                command: trimmedCommand,
                icon: selectedIcon
            )
            let newPreset = TerminalPreset(
                name: trimmedName,
                command: trimmedCommand,
                icon: selectedIcon
            )
            onSave(newPreset)
        }
        dismiss()
    }
}
