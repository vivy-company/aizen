//
//  GitSettingsView.swift
//  aizen
//

import SwiftUI

struct GitSettingsView: View {
    @StateObject private var templateManager = BranchTemplateManager.shared

    @State private var showingAddTemplate = false
    @State private var editingTemplate: BranchTemplate?

    var body: some View {
        Form {
            Section {
                ForEach(templateManager.templates) { template in
                    HStack(spacing: 12) {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.tertiary)
                            .font(.system(size: 12))

                        Image(systemName: template.icon)
                            .frame(width: 20)
                            .foregroundStyle(.secondary)

                        Text(template.prefix)

                        Spacer()

                        Button {
                            editingTemplate = template
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)

                        Button {
                            templateManager.deleteTemplate(id: template.id)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                }
                .onMove { source, destination in
                    templateManager.moveTemplate(from: source, to: destination)
                }

                Button {
                    showingAddTemplate = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color.accentColor)
                        Text("Add Template")
                    }
                }
                .buttonStyle(.plain)
            } header: {
                Text("Branch Templates")
            } footer: {
                Text("Templates appear as suggestions when creating new branches")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingAddTemplate) {
            BranchTemplateFormView(
                onSave: { _ in },
                onCancel: {}
            )
        }
        .sheet(item: $editingTemplate) { template in
            BranchTemplateFormView(
                existingTemplate: template,
                onSave: { _ in },
                onCancel: {}
            )
        }
    }
}
