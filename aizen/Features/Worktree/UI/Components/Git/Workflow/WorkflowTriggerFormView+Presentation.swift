import SwiftUI

extension WorkflowTriggerFormView {
    var header: some View {
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

    var loadingView: some View {
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

    var branchSelector: some View {
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

    var footer: some View {
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
}
