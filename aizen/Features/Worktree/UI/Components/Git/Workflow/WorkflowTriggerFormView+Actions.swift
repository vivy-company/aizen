import SwiftUI

extension WorkflowTriggerFormView {
    func binding(for input: WorkflowInput) -> Binding<String> {
        Binding(
            get: { inputValues[input.id] ?? input.defaultValue ?? input.type.defaultEmptyValue },
            set: { inputValues[input.id] = $0 }
        )
    }

    var canSubmit: Bool {
        guard !isSubmitting else { return false }
        guard !selectedBranch.isEmpty else { return false }

        for input in inputs where input.required {
            let value = inputValues[input.id] ?? input.defaultValue ?? ""
            if value.isEmpty {
                return false
            }
        }

        return true
    }

    func loadInputs() async {
        selectedBranch = currentBranch
        inputs = await service.getWorkflowInputs(workflow: workflow)

        for input in inputs {
            if let defaultValue = input.defaultValue {
                inputValues[input.id] = defaultValue
            }
        }

        isLoading = false
    }

    func triggerWorkflow() async {
        isSubmitting = true
        error = nil

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
