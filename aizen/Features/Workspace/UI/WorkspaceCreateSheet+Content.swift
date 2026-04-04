//
//  WorkspaceCreateSheet+Content.swift
//  aizen
//

import SwiftUI

extension WorkspaceCreateSheet {
    var formContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            nameSection
            colorSection

            if let error = errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding()
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("workspace.create.name", bundle: .main)
                .font(.headline)

            TextField(String(localized: "workspace.create.namePlaceholder"), text: $workspaceName)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("workspace.create.color", bundle: .main)
                .font(.headline)

            HStack(spacing: 12) {
                ForEach(availableColors, id: \.self) { color in
                    Circle()
                        .fill(color)
                        .frame(width: 30, height: 30)
                        .overlay {
                            if selectedColor == color {
                                Circle()
                                    .strokeBorder(.white, lineWidth: 3)
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.white)
                                    .font(.caption)
                            }
                        }
                        .onTapGesture {
                            selectedColor = color
                        }
                }
            }
        }
    }
}
