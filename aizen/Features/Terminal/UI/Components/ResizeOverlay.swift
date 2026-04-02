//
//  ResizeOverlay.swift
//  aizen
//
//  Overlay showing terminal dimensions during resize
//

import SwiftUI

struct ResizeOverlay: View {
    let columns: UInt16
    let rows: UInt16

    var body: some View {
        Text("\(columns)×\(rows)")
            .font(.system(.title, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.75))
            )
    }
}
