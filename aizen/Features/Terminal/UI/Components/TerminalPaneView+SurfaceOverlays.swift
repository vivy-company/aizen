import GhosttyKit
import SwiftUI

struct AizenSurfaceResizeOverlay: View {
    let geoSize: CGSize
    let size: ghostty_surface_size_s
    let focusInstant: ContinuousClock.Instant?

    @State private var lastSize: CGSize?
    @State private var ready = false

    private let padding: CGFloat = 5
    private let durationMs: UInt64 = 500

    private var hidden: Bool {
        if !ready { return true }
        if lastSize == geoSize { return true }
        if let instant = focusInstant {
            let delta = instant.duration(to: ContinuousClock.now)
            if delta < .milliseconds(500) {
                DispatchQueue.main.async {
                    lastSize = geoSize
                }
                return true
            }
        }
        return false
    }

    var body: some View {
        Text(verbatim: "\(size.columns) ⨯ \(size.rows)")
            .padding(.init(top: padding, leading: padding, bottom: padding, trailing: padding))
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(.background)
                    .shadow(radius: 3)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .allowsHitTesting(false)
            .opacity(hidden ? 0 : 1)
            .task {
                try? await Task.sleep(for: .milliseconds(500))
                ready = true
            }
            .task(id: geoSize) {
                if ready {
                    try? await Task.sleep(for: .milliseconds(durationMs))
                }
                lastSize = geoSize
            }
    }
}

struct AizenSurfaceProgressBar: View {
    let report: Ghostty.Action.ProgressReport

    private var color: Color {
        switch report.state {
        case .error: return .red
        case .pause: return .orange
        default: return .accentColor
        }
    }

    private var progress: UInt8? {
        if let v = report.progress { return v }
        if report.state == .pause { return 100 }
        return nil
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                if let progress {
                    Rectangle()
                        .fill(color)
                        .frame(width: geometry.size.width * CGFloat(progress) / 100, height: geometry.size.height)
                        .animation(.easeInOut(duration: 0.2), value: progress)
                } else {
                    AizenBouncingProgressBar(color: color)
                }
            }
        }
        .frame(height: 2)
        .clipped()
        .allowsHitTesting(false)
    }
}

struct AizenBouncingProgressBar: View {
    let color: Color
    @State private var position: CGFloat = 0

    private let barWidthRatio: CGFloat = 0.25

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(color.opacity(0.3))

                Rectangle()
                    .fill(color)
                    .frame(width: geometry.size.width * barWidthRatio, height: geometry.size.height)
                    .offset(x: position * (geometry.size.width * (1 - barWidthRatio)))
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                position = 1
            }
        }
        .onDisappear {
            position = 0
        }
    }
}
