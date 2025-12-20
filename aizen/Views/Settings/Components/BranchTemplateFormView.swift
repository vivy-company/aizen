//
//  BranchTemplateFormView.swift
//  aizen
//

import SwiftUI

struct BranchTemplateFormView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var prefix: String
    @State private var selectedIcon: String
    @State private var showingIconPicker = false

    let existingTemplate: BranchTemplate?
    let onSave: (BranchTemplate) -> Void
    let onCancel: () -> Void

    init(
        existingTemplate: BranchTemplate? = nil,
        onSave: @escaping (BranchTemplate) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.existingTemplate = existingTemplate
        self.onSave = onSave
        self.onCancel = onCancel

        if let template = existingTemplate {
            _prefix = State(initialValue: template.prefix)
            _selectedIcon = State(initialValue: template.icon)
        } else {
            _prefix = State(initialValue: "")
            _selectedIcon = State(initialValue: "arrow.triangle.branch")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(existingTemplate == nil ? "Add Branch Template" : "Edit Template")
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

            Form {
                Section("Template") {
                    TextField("Prefix", text: $prefix)
                        .help("Branch name prefix (e.g., feature/, bugfix/, hotfix/)")

                    Text("Example: \(prefix.isEmpty ? "feature/" : prefix)my-branch-name")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("Icon") {
                    HStack(spacing: 12) {
                        Image(systemName: selectedIcon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)

                        Text(selectedIcon)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        Button("Choose Symbol...") {
                            showingIconPicker = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button(existingTemplate == nil ? "Add" : "Save") {
                    saveTemplate()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 400, height: 300)
        .sheet(isPresented: $showingIconPicker) {
            SFSymbolPickerView(selectedSymbol: $selectedIcon, isPresented: $showingIconPicker)
        }
    }

    private var isValid: Bool {
        !prefix.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func saveTemplate() {
        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespaces)

        if let existing = existingTemplate {
            var updated = existing
            updated.prefix = trimmedPrefix
            updated.icon = selectedIcon
            BranchTemplateManager.shared.updateTemplate(updated)
            onSave(updated)
        } else {
            BranchTemplateManager.shared.addTemplate(prefix: trimmedPrefix, icon: selectedIcon)
            let newTemplate = BranchTemplate(prefix: trimmedPrefix, icon: selectedIcon)
            onSave(newTemplate)
        }
        dismiss()
    }
}
