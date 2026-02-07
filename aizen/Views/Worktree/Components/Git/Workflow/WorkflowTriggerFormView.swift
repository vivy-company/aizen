//
//  WorkflowTriggerFormView.swift
//  aizen
//
//  Form for triggering workflows with dispatch inputs
//

import SwiftUI

struct WorkflowTriggerFormView: View {
    let workflow: Workflow
    let currentBranch: String
    @ObservedObject var service: WorkflowService
    let onDismiss: () -> Void

    @State private var inputs: [WorkflowInput] = []
    @State private var inputValues: [String: String] = [:]
    @State private var selectedBranch: String = ""
    @State private var isLoading: Bool = true
    @State private var isSubmitting: Bool = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            GitWindowDivider()

            if isLoading {
                loadingView
            } else {
                // Form content
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        branchSelector

                        if !inputs.isEmpty {
                            inputsSection
                        } else {
                            noInputsMessage
                        }
                    }
                    .padding()
                }

                GitWindowDivider()

                // Footer with actions
                footer
            }
        }
        .frame(width: 450, height: 500)
        .task {
            await loadInputs()
        }
    }

    // MARK: - Header

    private var header: some View {
        DetailHeaderBar(showsBackground: false) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Run Workflow")
                    .font(.headline)

                Text(workflow.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } trailing: {
            DetailCloseButton(action: onDismiss, size: 16)
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
            Text("Loading workflow inputs...")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            Spacer()
        }
    }

    // MARK: - Branch Selector

    private var branchSelector: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Branch")
                .font(.subheadline)
                .fontWeight(.medium)

            TextField("Branch", text: $selectedBranch)
                .textFieldStyle(.roundedBorder)

            Text("The branch to run the workflow on")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Inputs Section

    private var inputsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Inputs")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            ForEach(inputs) { input in
                WorkflowInputFieldView(
                    input: input,
                    value: binding(for: input)
                )
            }
        }
    }

    private var noInputsMessage: some View {
        HStack {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)

            Text("This workflow has no configurable inputs")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if let error = error {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button("Cancel") {
                onDismiss()
            }
            .keyboardShortcut(.escape)

            Button {
                Task {
                    await triggerWorkflow()
                }
            } label: {
                if isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Run Workflow")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSubmit)
            .keyboardShortcut(.return)
        }
        .padding()
    }

    // MARK: - Helpers

    private func binding(for input: WorkflowInput) -> Binding<String> {
        Binding(
            get: { inputValues[input.id] ?? input.defaultValue ?? input.type.defaultEmptyValue },
            set: { inputValues[input.id] = $0 }
        )
    }

    private var canSubmit: Bool {
        guard !isSubmitting else { return false }
        guard !selectedBranch.isEmpty else { return false }

        // Check all required inputs have values
        for input in inputs where input.required {
            let value = inputValues[input.id] ?? input.defaultValue ?? ""
            if value.isEmpty {
                return false
            }
        }

        return true
    }

    private func loadInputs() async {
        selectedBranch = currentBranch
        inputs = await service.getWorkflowInputs(workflow: workflow)

        // Initialize default values
        for input in inputs {
            if let defaultValue = input.defaultValue {
                inputValues[input.id] = defaultValue
            }
        }

        isLoading = false
    }

    private func triggerWorkflow() async {
        isSubmitting = true
        error = nil

        // Build inputs dictionary (only non-empty values)
        var finalInputs: [String: String] = [:]
        for input in inputs {
            if let value = inputValues[input.id], !value.isEmpty {
                finalInputs[input.id] = value
            } else if let defaultValue = input.defaultValue {
                finalInputs[input.id] = defaultValue
            }
        }

        let success = await service.triggerWorkflow(workflow, branch: selectedBranch, inputs: finalInputs)

        if success {
            onDismiss()
        } else {
            error = service.error?.localizedDescription ?? "Failed to trigger workflow"
            isSubmitting = false
        }
    }
}

// MARK: - Input Field View

struct WorkflowInputFieldView: View {
    let input: WorkflowInput
    @Binding var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(input.displayName)
                    .font(.subheadline)

                if input.required {
                    Text("*")
                        .foregroundStyle(.red)
                }
            }

            inputField

            if !input.description.isEmpty {
                Text(input.description)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var inputField: some View {
        switch input.type {
        case .string:
            TextField("", text: $value)
                .textFieldStyle(.roundedBorder)

        case .boolean:
            Toggle("", isOn: boolBinding)
                .toggleStyle(.switch)
                .labelsHidden()

        case .choice(let options):
            Picker("", selection: $value) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

        case .environment:
            TextField("Environment", text: $value)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var boolBinding: Binding<Bool> {
        Binding(
            get: { value.lowercased() == "true" },
            set: { value = $0 ? "true" : "false" }
        )
    }
}
