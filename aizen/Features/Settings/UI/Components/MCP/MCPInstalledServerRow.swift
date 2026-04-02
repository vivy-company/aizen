//
//  MCPInstalledServerRow.swift
//  aizen
//
//  Row view for displaying an installed MCP server
//

import SwiftUI

struct MCPInstalledServerRow: View {
    let server: MCPInstalledServer
    let onRemove: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: iconName)
                .font(.body)
                .foregroundStyle(iconColor)
                .frame(width: 20)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(server.displayName)
                    .font(.body)

                HStack(spacing: 6) {
                    if let packageType = server.packageType {
                        Text(packageType)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    if let transportType = server.transportType {
                        Text(transportType)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Remove button
            if isHovering {
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var iconName: String {
        if server.transportType == "http" || server.transportType == "sse" {
            return "globe"
        }
        return "shippingbox"
    }

    private var iconColor: Color {
        if server.transportType == "http" || server.transportType == "sse" {
            return .blue
        }
        return .orange
    }
}
