//
//  WorkflowInputFieldView.swift
//  aizen
//
//  Input field rendering for workflow dispatch inputs
//

import SwiftUI

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
