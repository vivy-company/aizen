//
//  ShimmerEffect.swift
//  aizen
//
//  Shimmer animation effect for loading states
//

import SwiftUI

// Perf probe: disable shimmer animation to isolate CPU churn.
struct ShimmerEffect: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}
