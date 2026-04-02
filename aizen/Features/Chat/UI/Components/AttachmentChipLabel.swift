//
//  AttachmentChipLabel.swift
//  aizen
//
//  Shared attachment chip label content
//

import SwiftUI

struct AttachmentChipLabel<Icon: View>: View {
    let title: String
    let icon: Icon

    init(title: String, @ViewBuilder icon: () -> Icon) {
        self.title = title
        self.icon = icon()
    }

    var body: some View {
        HStack(spacing: 6) {
            icon
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }
}
