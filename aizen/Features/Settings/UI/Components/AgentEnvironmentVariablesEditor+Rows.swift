import SwiftUI

extension AgentEnvironmentVariablesEditor {
    var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray")
                .foregroundStyle(.tertiary)
            Text("No environment variables configured")
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    var variablesList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Name")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Value")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.trailing, actionButtonsWidth + 6)

            ForEach(variables.map(\.id), id: \.self) { id in
                variableRow(for: id)
            }
        }
    }

    @ViewBuilder
    func variableRow(for id: UUID) -> some View {
        if let variable = variable(for: id) {
            let isRevealed = revealedSecretIDs.contains(id)
            let isDuplicate = !variable.trimmedName.isEmpty && duplicateNames.contains(variable.trimmedName)

            HStack(spacing: 6) {
                PlainTextField(text: nameBinding(for: id), isDuplicate: isDuplicate)

                HStack(spacing: 4) {
                    if variable.isSecret && !isRevealed {
                        PlainSecureField(text: valueBinding(for: id))
                    } else {
                        PlainTextField(text: valueBinding(for: id))
                    }

                    if variable.isSecret {
                        Button {
                            toggleReveal(for: id)
                        } label: {
                            Image(systemName: isRevealed ? "eye.slash" : "eye")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                        .help(isRevealed ? "Hide value" : "Reveal value")
                    }
                }

                secureToggle(for: id, variable: variable)

                Button(role: .destructive) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        removeVariable(id: id)
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Remove variable")
            }
        }
    }

    func secureToggle(for id: UUID, variable: AgentEnvironmentVariable) -> some View {
        Button {
            guard let index = variables.firstIndex(where: { $0.id == id }) else { return }
            variables[index].isSecret.toggle()
            if !variables[index].isSecret {
                revealedSecretIDs.remove(id)
            }
        } label: {
            Image(systemName: variable.isSecret ? "lock.fill" : "lock.open")
                .font(.caption)
                .foregroundStyle(variable.isSecret ? Color.blue : Color.secondary.opacity(0.4))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(variable.isSecret ? "Secured — value is stored in macOS Keychain. Click to store as plain text instead." : "Unsecured — value is stored as plain text. Click to protect with macOS Keychain.")
    }

    func variable(for id: UUID) -> AgentEnvironmentVariable? {
        variables.first(where: { $0.id == id })
    }

    func nameBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { variable(for: id)?.name ?? "" },
            set: { newValue in
                guard let index = variables.firstIndex(where: { $0.id == id }) else { return }
                variables[index].name = newValue
            }
        )
    }

    func valueBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { variable(for: id)?.value ?? "" },
            set: { newValue in
                guard let index = variables.firstIndex(where: { $0.id == id }) else { return }
                variables[index].value = newValue
            }
        )
    }

    func toggleReveal(for id: UUID) {
        if revealedSecretIDs.contains(id) {
            revealedSecretIDs.remove(id)
        } else {
            revealedSecretIDs.insert(id)
        }
    }

    func removeVariable(id: UUID) {
        variables.removeAll { $0.id == id }
        revealedSecretIDs.remove(id)
    }
}
