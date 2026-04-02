//
//  IndeterminateBar.swift
//  aizen
//

import SwiftUI

struct IndeterminateBar: View {
    let color: Color
    @State private var phase: CGFloat = -0.3

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let barWidth = max(12, width * 0.22)
            Rectangle()
                .fill(color)
                .frame(width: barWidth, height: geo.size.height)
                .offset(x: phase * width)
                .animation(.linear(duration: 0.85).repeatForever(autoreverses: true), value: phase)
                .onAppear { phase = 1.0 }
        }
        .clipped()
    }
}
