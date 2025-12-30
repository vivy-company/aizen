//
//  ShimmerEffect.swift
//  aizen
//
//  Shimmer animation effect for loading states
//

import SwiftUI

struct ShimmerEffect: ViewModifier {
    private let gradient: Gradient
    private let bandSize: CGFloat
    private let duration: Double

    @State private var phase: CGFloat = 0
    @Environment(\.layoutDirection) private var layoutDirection

    init(
        gradient: Gradient = Gradient(colors: [
            .white.opacity(0.4),
            .white,
            .white.opacity(0.4)
        ]),
        bandSize: CGFloat = 0.3,
        duration: Double = 1.5
    ) {
        self.gradient = gradient
        self.bandSize = bandSize
        self.duration = duration
    }

    func body(content: Content) -> some View {
        let startX = phase - bandSize
        let endX = phase + bandSize

        content
            .mask(
                LinearGradient(
                    gradient: gradient,
                    startPoint: UnitPoint(x: layoutDirection == .rightToLeft ? 1 - startX : startX, y: 0),
                    endPoint: UnitPoint(x: layoutDirection == .rightToLeft ? 1 - endX : endX, y: 0)
                )
            )
            .onAppear {
                withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                    phase = 1 + bandSize * 2
                }
            }
    }
}
