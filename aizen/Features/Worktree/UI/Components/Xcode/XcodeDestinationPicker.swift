//
//  XcodeDestinationPicker.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 10.12.25.
//

import SwiftUI

struct XcodeDestinationPicker: View {
    @ObservedObject var buildManager: XcodeBuildStore

    var body: some View {
        Menu {
            // Scheme picker (if multiple schemes)
            if let project = buildManager.detectedProject, project.schemes.count > 1 {
                schemeSection(project: project)
                Divider()
            }

            // Destinations by type
            destinationSections
        } label: {
            menuLabel
        }
        .buttonStyle(.borderless)
        .padding(8)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(buildManager.currentPhase.isBuilding)
    }

    // MARK: - Menu Label

    @ViewBuilder
    private var menuLabel: some View {
        HStack(spacing: 4) {
            if let destination = buildManager.selectedDestination {
                destinationIcon(for: destination)
                Text(destination.name)
                    .font(.system(size: 11))
                    .lineLimit(1)
            } else {
                Text("Select Destination")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            if buildManager.isLoadingDestinations {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
            } else {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
        }
    }

}

#Preview {
    XcodeDestinationPicker(buildManager: XcodeBuildStore())
        .padding()
}
