//
//  XcodeDestinationPicker+Label.swift
//  aizen
//
//  Created by OpenAI Codex on 06.04.26.
//

import SwiftUI

extension XcodeDestinationPicker {
    @ViewBuilder
    var menuLabel: some View {
        HStack(spacing: 4) {
            if let destination = buildManager.selectedDestination {
                destinationIcon(for: destination)
                Text(destination.name)
                    .font(.system(size: 11))
                    .lineLimit(1)
            } else {
                Text("Select Destination")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            if buildManager.isLoadingDestinations {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
            } else {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
