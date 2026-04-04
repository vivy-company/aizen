import ACPRegistry
import SwiftUI

struct RegistryAgentRow: View {
    let agent: RegistryAgent
    let isAdded: Bool
    let isAdding: Bool
    let onAdd: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RegistryRemoteIconView(iconURL: agent.icon, size: 28) {
                Image(systemName: "brain.head.profile")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.secondary)
                    .padding(4)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(agent.name)
                        .font(.headline)
                    Text(agent.version)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(agent.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                HStack(spacing: 6) {
                    ForEach(distributionBadges, id: \.self) { badge in
                        TagBadge(
                            text: badge,
                            color: .secondary,
                            font: .caption2,
                            horizontalPadding: 8,
                            verticalPadding: 4,
                            backgroundOpacity: 0.14,
                            textColor: .secondary
                        )
                    }

                    if let repository = agent.repository,
                       let repositoryURL = URL(string: repository) {
                        Link("Repository", destination: repositoryURL)
                            .font(.caption2)
                    }
                }
            }

            Spacer(minLength: 12)

            actionView
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .modifier(SelectableRowModifier(
            isSelected: false,
            isHovered: isHovered,
            showsIdleBackground: false,
            cornerRadius: 0
        ))
        .onHover { hovering in
            isHovered = hovering
        }
    }

    @ViewBuilder
    private var actionView: some View {
        if isAdded {
            Text("Added")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        } else if isAdding {
            ProgressView()
                .controlSize(.small)
                .padding(.top, 4)
        } else {
            Button("Add") {
                onAdd()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var distributionBadges: [String] {
        var badges: [String] = []
        if agent.distribution.binary != nil {
            badges.append("Binary")
        }
        if agent.distribution.npx != nil {
            badges.append("NPX")
        }
        if agent.distribution.uvx != nil {
            badges.append("UVX")
        }
        return badges
    }
}
