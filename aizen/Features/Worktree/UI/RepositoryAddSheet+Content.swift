//
//  RepositoryAddSheet+Content.swift
//  aizen
//

import SwiftUI

extension RepositoryAddSheet {
    @ViewBuilder
    var formContent: some View {
        modeSection

        if mode == .clone {
            cloneSection
        } else if mode == .create {
            createSection
        } else {
            existingSection
        }

        if let error = errorMessage {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.callout)
                        Text("Add project failed")
                            .font(.callout)
                            .fontWeight(.semibold)
                    }
                    Text(error)
                        .font(.system(.caption, design: .monospaced))
                }
                .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var modeSection: some View {
        Section("Project Source") {
            Picker("Mode", selection: $mode) {
                ForEach(AddRepositoryMode.allCases, id: \.self) { mode in
                    Text(mode.title)
                        .tag(mode)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var cloneSection: some View {
        Section("Clone") {
            LabeledContent(String(localized: "repository.add.url", bundle: .main)) {
                TextField(String(localized: "repository.add.urlPlaceholder"), text: $cloneURL)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280, alignment: .leading)
            }

            pathPickerRow(
                title: String(localized: "repository.cloneLocation", bundle: .main),
                placeholder: String(localized: "repository.selectDestination"),
                action: selectCloneDestination
            )

            Text("repository.cloneDescription", bundle: .main)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var existingSection: some View {
        Section("Existing Repository") {
            pathPickerRow(
                title: String(localized: "repository.selectLocation", bundle: .main),
                placeholder: String(localized: "repository.selectFolder"),
                action: selectExistingRepository
            )

            Text("repository.selectGitFolder", bundle: .main)
                .font(.caption)
                .foregroundStyle(.secondary)

            if !selectedPath.isEmpty {
                selectedPathPreview
            }
        }
    }

    @ViewBuilder
    private var createSection: some View {
        Section("Create Repository") {
            pathPickerRow(
                title: String(localized: "repository.newLocation", bundle: .main),
                placeholder: String(localized: "repository.selectFolder"),
                action: selectNewRepositoryLocation
            )

            LabeledContent(String(localized: "repository.create.name", bundle: .main)) {
                TextField(String(localized: "repository.create.namePlaceholder"), text: $repositoryName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280, alignment: .leading)
            }

            Text("repository.create.description", bundle: .main)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var selectedPathPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("repository.add.selected", bundle: .main)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(selectedPath)
                .font(.caption)
                .fontDesign(.monospaced)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    @ViewBuilder
    private func pathPickerRow(title: String, placeholder: String, action: @escaping () -> Void) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Text(selectedPath.isEmpty ? placeholder : selectedPath)
                    .font(selectedPath.isEmpty ? .body : .system(.body, design: .monospaced))
                    .foregroundStyle(selectedPath.isEmpty ? .tertiary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(width: 280, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
                    }

                Button(String(localized: "repository.add.choose")) {
                    action()
                }
            }
        }
    }
}
