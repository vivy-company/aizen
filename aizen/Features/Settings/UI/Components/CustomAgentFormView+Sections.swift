//
//  CustomAgentFormView+Sections.swift
//  aizen
//

import SwiftUI

extension CustomAgentFormView {
    @ViewBuilder
    var basicInformationSection: some View {
        Section("Basic Information") {
            TextField("Name", text: $name)
                .help("Display name for the agent")

            TextField("Description (optional)", text: $description, axis: .vertical)
                .lineLimit(2...4)
                .help("Brief description of the agent")
        }
    }

    @ViewBuilder
    var iconSection: some View {
        Section("Icon") {
            HStack(spacing: 12) {
                Image(systemName: selectedSFSymbol)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)

                Text(selectedSFSymbol)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button("Choose Symbol...") {
                    showingSFSymbolPicker = true
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
