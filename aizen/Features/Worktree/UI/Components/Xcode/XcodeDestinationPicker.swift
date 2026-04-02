//
//  XcodeDestinationPicker.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 10.12.25.
//

import SwiftUI

struct XcodeDestinationPicker: View {
    @ObservedObject var buildManager: XcodeBuildManager

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

    // MARK: - Scheme Section

    @ViewBuilder
    private func schemeSection(project: XcodeProject) -> some View {
        Section("Scheme") {
            ForEach(project.schemes, id: \.self) { scheme in
                Button {
                    buildManager.selectScheme(scheme)
                } label: {
                    HStack {
                        Text(scheme)
                        if scheme == buildManager.selectedScheme {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Destination Sections

    @ViewBuilder
    private var destinationSections: some View {
        // Simulators
        if let simulators = buildManager.availableDestinations[.simulator], !simulators.isEmpty {
            Section("Simulators") {
                ForEach(groupedSimulators(simulators), id: \.key) { platform, devices in
                    Section(platform) {
                        ForEach(devices) { destination in
                            destinationButton(destination)
                        }
                    }
                }
            }
        }

        // My Mac
        if let macs = buildManager.availableDestinations[.mac], !macs.isEmpty {
            Section("My Mac") {
                ForEach(macs) { destination in
                    destinationButton(destination)
                }
            }
        }

        // Connected Devices
        if let devices = buildManager.availableDestinations[.device], !devices.isEmpty {
            Section("Connected Devices") {
                ForEach(devices) { destination in
                    destinationButton(destination)
                }
            }
        }

        // Refresh button
        Divider()
        Button {
            buildManager.refreshDestinations()
        } label: {
            if buildManager.isLoadingDestinations {
                Label("Refreshing...", systemImage: "arrow.clockwise")
            } else {
                Label("Refresh Devices", systemImage: "arrow.clockwise")
            }
        }
        .disabled(buildManager.isLoadingDestinations)
    }

    // MARK: - Destination Button

    @ViewBuilder
    private func destinationButton(_ destination: XcodeDestination) -> some View {
        Button {
            buildManager.selectDestination(destination)
        } label: {
            HStack {
                destinationIcon(for: destination)
                VStack(alignment: .leading, spacing: 0) {
                    Text(destination.name)
                    if let version = destination.osVersion, destination.type != .mac {
                        Text(version)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if destination.id == buildManager.selectedDestination?.id {
                    Image(systemName: "checkmark")
                }
            }
        }
    }

    // MARK: - Helpers

    private func destinationIcon(for destination: XcodeDestination) -> some View {
        let iconName: String
        switch destination.type {
        case .mac:
            iconName = "laptopcomputer"
        case .simulator, .device:
            if destination.name.lowercased().contains("ipad") {
                iconName = "ipad"
            } else if destination.name.lowercased().contains("watch") {
                iconName = "applewatch"
            } else if destination.name.lowercased().contains("tv") {
                iconName = "appletv"
            } else if destination.name.lowercased().contains("vision") {
                iconName = "visionpro"
            } else {
                iconName = "iphone"
            }
        }

        return Image(systemName: iconName)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
    }

    private func groupedSimulators(_ simulators: [XcodeDestination]) -> [(key: String, value: [XcodeDestination])] {
        let grouped = Dictionary(grouping: simulators) { $0.platform }
        return grouped.sorted { lhs, rhs in
            // iOS first
            if lhs.key == "iOS" { return true }
            if rhs.key == "iOS" { return false }
            return lhs.key < rhs.key
        }
    }
}

#Preview {
    XcodeDestinationPicker(buildManager: XcodeBuildManager())
        .padding()
}
