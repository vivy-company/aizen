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

    var body: some View {
        HStack(spacing: 6) {
            AgentIconView(agent: agentId, size: 12)
            Text(title)
                .font(.system(size: 11, weight: .medium))
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
