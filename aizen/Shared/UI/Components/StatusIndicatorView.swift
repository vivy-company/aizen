//
//  StatusIndicatorView.swift
//  aizen
//

import SwiftUI

struct StatusIndicatorView: View {
    let status: ItemStatus
    var size: CGFloat = 8
    var showLabel: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(status.color)
                .frame(width: size, height: size)

            if showLabel {
                Text(status.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .help(status.title)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        ForEach(ItemStatus.allCases) { status in
            HStack {
                StatusIndicatorView(status: status)
                StatusIndicatorView(status: status, showLabel: true)
            }
        }
    }
    .padding()
}
