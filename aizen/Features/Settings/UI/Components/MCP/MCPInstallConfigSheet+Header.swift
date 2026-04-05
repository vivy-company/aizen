import SwiftUI

extension MCPInstallConfigSheet {
    var headerView: some View {
        DetailHeaderBar(showsBackground: false) {
            HStack(alignment: .top, spacing: 12) {
                if let icon = server.primaryIcon, let iconUrl = icon.iconUrl, let url = URL(string: iconUrl) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 40, height: 40)
                                .cornerRadius(8)
                        default:
                            serverIcon
                        }
                    }
                } else {
                    serverIcon
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(server.displayTitle)
                            .font(.headline)

                        if let version = server.version {
                            TagBadge(text: "v\(version)", color: .secondary)
                        }
                    }

                    Text("Adding to Aizen MCP defaults for \(agentName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        } trailing: {
            HStack(spacing: 8) {
                if let websiteUrl = server.websiteUrl, let url = URL(string: websiteUrl) {
                    Link(destination: url) {
                        Image(systemName: "globe")
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    .help("Open Website")
                }

                if let repoUrl = server.repository?.url, let url = URL(string: repoUrl) {
                    Link(destination: url) {
                        Image(systemName: "link")
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    .help("Open Project")
                }
            }
        }
        .background(AppSurfaceTheme.backgroundColor())
    }
}
