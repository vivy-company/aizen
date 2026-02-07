//
//  AgentMenuLabel.swift
//  aizen
//
//  Shared label used by agent selection menus
//

import SwiftUI

struct AgentMenuLabel: View {
    let agentId: String
    let title: String
    var showsChevron: Bool = true
    var showsIcon: Bool = true
    var showsBackground: Bool = true
    var titleFontSize: CGFloat = 11
    var iconSize: CGFloat = 12
    var chevronSize: CGFloat = 8

    var body: some View {
        HStack(spacing: 6) {
            if showsIcon {
                AgentIconView(agent: agentId, size: iconSize)
            }
            Text(title)
                .font(.system(size: titleFontSize, weight: .medium))
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: chevronSize))
            }
        }
        .padding(.horizontal, showsBackground ? 8 : 0)
        .padding(.vertical, showsBackground ? 4 : 0)
        .background {
            if showsBackground {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        }
    }
}
