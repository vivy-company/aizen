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
                        Text("v\(version)")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .foregroundColor(.secondary)
                            .cornerRadius(4)
                    }

                    if isInstalled {
                        Text("Installed")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.2))
                            .foregroundColor(.green)
                            .cornerRadius(4)
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
                            Badge(text: package.registryBadge, color: .purple)
                            Badge(text: package.transportType, color: .gray)
                        } else if let remote = server.primaryRemote {
                            Badge(text: remote.transportBadge, color: .blue)
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

// MARK: - Badge

private struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(4)
    }
}
