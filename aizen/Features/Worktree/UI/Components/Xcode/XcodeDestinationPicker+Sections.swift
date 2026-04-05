import SwiftUI

extension XcodeDestinationPicker {
    @ViewBuilder
    func schemeSection(project: XcodeProject) -> some View {
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

    @ViewBuilder
    var destinationSections: some View {
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

        if let macs = buildManager.availableDestinations[.mac], !macs.isEmpty {
            Section("My Mac") {
                ForEach(macs) { destination in
                    destinationButton(destination)
                }
            }
        }

        if let devices = buildManager.availableDestinations[.device], !devices.isEmpty {
            Section("Connected Devices") {
                ForEach(devices) { destination in
                    destinationButton(destination)
                }
            }
        }

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

    @ViewBuilder
    func destinationButton(_ destination: XcodeDestination) -> some View {
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

    func destinationIcon(for destination: XcodeDestination) -> some View {
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

    func groupedSimulators(_ simulators: [XcodeDestination]) -> [(key: String, value: [XcodeDestination])] {
        let grouped = Dictionary(grouping: simulators) { $0.platform }
        return grouped.sorted { lhs, rhs in
            if lhs.key == "iOS" { return true }
            if rhs.key == "iOS" { return false }
            return lhs.key < rhs.key
        }
    }
}
