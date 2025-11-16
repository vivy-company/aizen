//
//  FileIconView.swift
//  aizen
//
//  SwiftUI view for displaying file type icons.
//

import SwiftUI

struct FileIconView: View {
    let path: String
    let size: CGFloat

    @State private var icon: NSImage?

    init(path: String, size: CGFloat = 16) {
        self.path = path
        self.size = size
    }

    var body: some View {
        Group {
            if let icon = icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: size, height: size)
            } else {
                // Placeholder while loading
                Image(systemName: "doc")
                    .resizable()
                    .frame(width: size, height: size)
                    .foregroundColor(.secondary)
            }
        }
        .task(id: path) {
            // Load icon asynchronously - only re-runs when path changes
            icon = await FileIconService.shared.icon(
                forFile: path,
                size: CGSize(width: size, height: size)
            )
        }
    }
}
