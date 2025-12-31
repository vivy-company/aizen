//
//  MCPServerRowView.swift
//  aizen
//
//  Row view for displaying an MCP server in the marketplace
//

import SwiftUI

struct MCPServerRowView: View {
    let server: MCPServer
    let isInstalled: Bool
    let onInstall: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Icon
            Image(systemName: server.isRemoteOnly ? "globe" : "shippingbox.fill")
                .font(.title2)
                .foregroundStyle(server.isRemoteOnly ? .blue : .orange)
                .frame(width: 32)

            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(server.displayTitle)
                        .font(.headline)

                    if let version = server.version {
                        TagBadge(text: "v\(version)", color: .secondary, cornerRadius: 4)
                    }

                    if isInstalled {
                        TagBadge(text: "Installed", color: .green, cornerRadius: 4)
                    }
                }

                if let description = server.description {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                if server.primaryPackage != nil || server.primaryRemote != nil {
                    HStack(spacing: 8) {
                        if let package = server.primaryPackage {
                            TagBadge(text: package.registryBadge, color: .purple)
                            TagBadge(text: package.transportType, color: .gray)
                        } else if let remote = server.primaryRemote {
                            TagBadge(text: remote.transportBadge, color: .blue)
                        }
                    }
                }
            }

            Spacer()

            // Action
            if isInstalled {
                Button("Remove") {
                    onRemove()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button("Install") {
                    onInstall()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 8)
    }
}
