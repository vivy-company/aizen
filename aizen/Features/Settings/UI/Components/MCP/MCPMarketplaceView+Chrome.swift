//
//  MCPMarketplaceView+Chrome.swift
//  aizen
//

import SwiftUI

extension MCPMarketplaceView {
    enum ServerFilter: String, CaseIterable {
        case all = "All"
        case installed = "Added"
        case remote = "Remote"
        case package = "Package"

        var icon: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .installed: return "checkmark.circle"
            case .remote: return "globe"
            case .package: return "shippingbox"
            }
        }
    }

    var surfaceColor: Color {
        AppSurfaceTheme.backgroundColor(colorScheme: colorScheme)
    }

    var headerView: some View {
        HStack(spacing: 12) {
            SearchField(
                placeholder: "Search MCP servers...",
                text: $searchQuery,
                iconColor: .secondary,
                onSubmit: {
                    Task { await searchImmediately() }
                },
                onClear: {
                    searchQuery = ""
                },
                trailing: { EmptyView() }
            )
            .padding(8)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)

            TagBadge(
                text: agentName,
                color: .accentColor,
                cornerRadius: 4,
                font: .caption,
                horizontalPadding: 8,
                verticalPadding: 4,
                backgroundOpacity: 0.15,
                textColor: .accentColor
            )

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(surfaceColor)
    }

    var filterTabsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(ServerFilter.allCases, id: \.self) { filter in
                    filterTab(filter)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    func filterTab(_ filter: ServerFilter) -> some View {
        Button {
            selectedFilter = filter
        } label: {
            HStack(spacing: 4) {
                Image(systemName: filter.icon)
                    .font(.system(size: 11))
                Text(filter.rawValue)
                    .font(.system(size: 11, weight: selectedFilter == filter ? .semibold : .regular))

                if filter == .installed {
                    let count = mcpManager.servers(for: agentId).count
                    if count > 0 {
                        TagBadge(
                            text: "\(count)",
                            color: .accentColor,
                            font: .system(size: 10, weight: .medium),
                            horizontalPadding: 5,
                            verticalPadding: 1,
                            backgroundOpacity: 0.2
                        )
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                selectedFilter == filter ?
                Color.accentColor.opacity(0.15) :
                Color.clear
            )
            .foregroundColor(selectedFilter == filter ? .accentColor : .secondary)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}
