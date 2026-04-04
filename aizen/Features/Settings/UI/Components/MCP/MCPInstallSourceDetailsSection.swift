//
//  MCPInstallSourceDetailsSection.swift
//  aizen
//
//  Created by OpenAI Codex on 05.04.26.
//

import SwiftUI

struct MCPInstallSourceDetailsSection: View {
    enum Source {
        case package(server: MCPServer, selectedPackageIndex: Binding<Int>, selectedPackage: MCPPackage?)
        case remote(server: MCPServer, selectedRemoteIndex: Binding<Int>, selectedRemote: MCPRemote?)
    }

    let source: Source

    var body: some View {
        switch source {
        case .package(let server, let selectedPackageIndex, let selectedPackage):
            packageSection(
                server: server,
                selectedPackageIndex: selectedPackageIndex,
                selectedPackage: selectedPackage
            )
        case .remote(let server, let selectedRemoteIndex, let selectedRemote):
            remoteSection(
                server: server,
                selectedRemoteIndex: selectedRemoteIndex,
                selectedRemote: selectedRemote
            )
        }
    }

    static func package(
        server: MCPServer,
        selectedPackageIndex: Binding<Int>,
        selectedPackage: MCPPackage?
    ) -> MCPInstallSourceDetailsSection {
        MCPInstallSourceDetailsSection(
            source: .package(
                server: server,
                selectedPackageIndex: selectedPackageIndex,
                selectedPackage: selectedPackage
            )
        )
    }

    static func remote(
        server: MCPServer,
        selectedRemoteIndex: Binding<Int>,
        selectedRemote: MCPRemote?
    ) -> MCPInstallSourceDetailsSection {
        MCPInstallSourceDetailsSection(
            source: .remote(
                server: server,
                selectedRemoteIndex: selectedRemoteIndex,
                selectedRemote: selectedRemote
            )
        )
    }

    @ViewBuilder
    private func packageSection(
        server: MCPServer,
        selectedPackageIndex: Binding<Int>,
        selectedPackage: MCPPackage?
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Package")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.secondary)

                if server.packages!.count > 1 {
                    Picker("Package", selection: selectedPackageIndex) {
                        ForEach(Array(server.packages!.enumerated()), id: \.offset) { index, pkg in
                            Text("\(pkg.registryBadge): \(pkg.packageName)").tag(index)
                        }
                    }
                    .labelsHidden()
                } else if let package = selectedPackage {
                    HStack(spacing: 8) {
                        TagBadge(text: package.registryBadge, color: .purple)
                        TagBadge(text: package.transportType, color: .gray)
                        Text(package.packageName)
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }

            if let package = selectedPackage {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Runtime")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 4) {
                        CodePill(
                            text: package.runtimeHint,
                            font: .system(.caption, design: .monospaced),
                            backgroundColor: Color(NSColor.textBackgroundColor),
                            horizontalPadding: 8,
                            verticalPadding: 4
                        )

                        if let runtimeArgs = package.runtimeArguments, !runtimeArgs.isEmpty {
                            CodePill(
                                text: runtimeArgs.map { $0.displayValue }.joined(separator: " "),
                                font: .system(.caption, design: .monospaced),
                                textColor: .secondary,
                                backgroundColor: Color(NSColor.textBackgroundColor),
                                horizontalPadding: 8,
                                verticalPadding: 4
                            )
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func remoteSection(
        server: MCPServer,
        selectedRemoteIndex: Binding<Int>,
        selectedRemote: MCPRemote?
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Remote")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.secondary)

                if server.remotes!.count > 1 {
                    Picker("Remote", selection: selectedRemoteIndex) {
                        ForEach(Array(server.remotes!.enumerated()), id: \.offset) { index, remote in
                            Text("\(remote.transportBadge): \(remote.url)").tag(index)
                        }
                    }
                    .labelsHidden()
                } else if let remote = selectedRemote {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            TagBadge(text: remote.transportBadge, color: .blue)
                            TagBadge(text: "Remote", color: .teal)
                        }

                        CodePill(
                            text: remote.url,
                            font: .system(.caption, design: .monospaced),
                            backgroundColor: Color(NSColor.textBackgroundColor),
                            horizontalPadding: 8,
                            verticalPadding: 4,
                            selectable: true,
                            lineLimit: 1
                        )
                    }
                }
            }

            if let remote = selectedRemote, let headers = remote.headers, !headers.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Required Headers")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ForEach(headers, id: \.name) { header in
                        HStack {
                            Text(header.name)
                                .font(.system(.caption, design: .monospaced))
                            if header.isRequired == true {
                                Text("*")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
            }
        }
    }
}
