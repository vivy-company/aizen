//
//  ScaledProgressView.swift
//  aizen
//
//  Small progress indicator with consistent sizing
//

import SwiftUI

struct ScaledProgressView: View {
    var size: CGFloat
    var scale: CGFloat = 0.5

    var body: some View {
        ProgressView()
            .scaleEffect(scale)
            .frame(width: size, height: size)
    }
}
