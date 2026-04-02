import SwiftUI

struct PostCreateTemplatesSheet: View {
    let onSelect: (PostCreateTemplate) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var templateManager = PostCreateTemplateStore.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Apply Template")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()
            }
            .padding()

            Divider()

            ScrollView {
                LazyVStack(spacing: 8) {
                    Section {
                        ForEach(PostCreateTemplate.builtInTemplates) { template in
                            templateRow(template, isBuiltIn: true)
                        }
                    } header: {
                        sectionHeader("Built-in Templates")
                    }

                    if !templateManager.customTemplates.isEmpty {
                        Section {
                            ForEach(templateManager.customTemplates) { template in
                                templateRow(template, isBuiltIn: false)
                            }
                        } header: {
                            sectionHeader("Custom Templates")
                        }
                    }
                }
                .padding()
            }

            Divider()

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(width: 400, height: 450)
        .settingsSheetChrome()
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }

    private func templateRow(_ template: PostCreateTemplate, isBuiltIn: Bool) -> some View {
        Button {
            onSelect(template)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: template.icon)
                    .font(.title2)
                    .frame(width: 32)
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name)
                        .fontWeight(.medium)

                    Text("\(template.actions.count) action\(template.actions.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isBuiltIn {
                    PillBadge(
                        text: "Built-in",
                        color: Color(.systemGray),
                        textColor: .secondary,
                        font: .caption2,
                        horizontalPadding: 6,
                        verticalPadding: 2,
                        backgroundOpacity: 0.2
                    )
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
