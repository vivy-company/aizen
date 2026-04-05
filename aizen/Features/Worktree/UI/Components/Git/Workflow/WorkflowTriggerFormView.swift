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

    @State var inputs: [WorkflowInput] = []
    @State var inputValues: [String: String] = [:]
    @State var selectedBranch: String = ""
    @State var isLoading: Bool = true
    @State var isSubmitting: Bool = false
    @State var error: String?

    var body: some View {
        VStack(spacing: 0) {
            header

            GitWindowDivider()

            if isLoading {
                loadingView
            } else {
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

                footer
            }
        }
        .frame(width: 450, height: 500)
        .task {
            await loadInputs()
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

    // MARK: - Helpers

}
