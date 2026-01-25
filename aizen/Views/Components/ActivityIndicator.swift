//
//  ActivityIndicator.swift
//  aizen
//
//  Animated activity indicators for agent thinking and processing states
//

import SwiftUI

// MARK: - Thinking Dots Animation

struct ThinkingDotsView: View {
    private let dotCount = 3
    private let dotSize: CGFloat = 6
    private let spacing: CGFloat = 4
    private let interval: TimeInterval = 0.4
    
    var body: some View {
        TimelineView(.periodic(from: .now, by: interval)) { timeline in
            let phase = Int(timeline.date.timeIntervalSinceReferenceDate / interval) % dotCount
            HStack(spacing: spacing) {
                ForEach(0..<dotCount, id: \.self) { index in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: dotSize, height: dotSize)
                        .scaleEffect(scaleForDot(at: index, phase: phase))
                        .opacity(opacityForDot(at: index, phase: phase))
                        .animation(.easeInOut(duration: 0.3), value: phase)
                }
            }
        }
    }
    
    private func scaleForDot(at index: Int, phase: Int) -> CGFloat {
        let adjustedPhase = (phase + index) % dotCount
        switch adjustedPhase {
        case 0: return 1.0
        case 1: return 0.7
        default: return 0.5
        }
    }
    
    private func opacityForDot(at index: Int, phase: Int) -> Double {
        let adjustedPhase = (phase + index) % dotCount
        switch adjustedPhase {
        case 0: return 1.0
        case 1: return 0.6
        default: return 0.3
        }
    }
}

// MARK: - Pulsing Dot

struct PulsingDotView: View {
    let color: Color
    let size: CGFloat
    
    @State private var isPulsing = false
    
    init(color: Color = .blue, size: CGFloat = 8) {
        self.color = color
        self.size = size
    }
    
    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.3))
                .frame(width: size * 2, height: size * 2)
                .scaleEffect(isPulsing ? 1.5 : 1.0)
                .opacity(isPulsing ? 0 : 0.5)
            
            Circle()
                .fill(color)
                .frame(width: size, height: size)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
        }
    }
}

// MARK: - Typing Indicator

struct TypingIndicatorView: View {
    let agentName: String?
    
    @State private var dotOffsets: [CGFloat] = [0, 0, 0]
    
    var body: some View {
        HStack(spacing: 8) {
            if let agentName = agentName {
                AgentIconView(agent: agentName, size: 20)
            }
            
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 6, height: 6)
                        .offset(y: dotOffsets[index])
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                    )
            )
        }
        .onAppear {
            animateDots()
        }
    }
    
    private func animateDots() {
        for i in 0..<3 {
            withAnimation(
                .easeInOut(duration: 0.5)
                .repeatForever(autoreverses: true)
                .delay(Double(i) * 0.15)
            ) {
                dotOffsets[i] = -6
            }
        }
    }
}

// MARK: - Streaming Glow Effect

struct StreamingGlowModifier: ViewModifier {
    let isActive: Bool
    let color: Color
    
    @State private var glowOpacity: Double = 0.3
    
    init(isActive: Bool, color: Color = .blue) {
        self.isActive = isActive
        self.color = color
    }
    
    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(color.opacity(isActive ? glowOpacity : 0), lineWidth: 2)
                    .blur(radius: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(color.opacity(isActive ? glowOpacity * 0.5 : 0), lineWidth: 1)
            )
            .onChange(of: isActive) { _, active in
                if active {
                    withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                        glowOpacity = 0.6
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.3)) {
                        glowOpacity = 0
                    }
                }
            }
            .onAppear {
                if isActive {
                    withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                        glowOpacity = 0.6
                    }
                }
            }
    }
}

extension View {
    func streamingGlow(isActive: Bool, color: Color = .blue) -> some View {
        modifier(StreamingGlowModifier(isActive: isActive, color: color))
    }
}

// MARK: - Progress Spinner

struct ProgressSpinnerView: View {
    let size: CGFloat
    let lineWidth: CGFloat
    let color: Color
    
    @State private var isAnimating = false
    
    init(size: CGFloat = 16, lineWidth: CGFloat = 2, color: Color = .blue) {
        self.size = size
        self.lineWidth = lineWidth
        self.color = color
    }
    
    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(isAnimating ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
    }
}

// MARK: - Agent Thinking View

struct AgentThinkingView: View {
    let agentName: String
    let thought: String?
    let renderMarkdown: (String) -> AttributedString
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.96)
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AgentIconView(agent: agentName, size: 24)
                .overlay(alignment: .bottomTrailing) {
                    PulsingDotView(color: .blue, size: 6)
                        .offset(x: 2, y: 2)
                }
            
            VStack(alignment: .leading, spacing: 4) {
                if let thought = thought, !thought.isEmpty {
                    Text(renderMarkdown(thought))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .modifier(ShimmerEffect(bandSize: 0.3, duration: 2.0))
                } else {
                    HStack(spacing: 8) {
                        Text("Thinking")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                        
                        ThinkingDotsView()
                    }
                }
            }
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.blue.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Previews

#Preview("Thinking Dots") {
    VStack(spacing: 20) {
        ThinkingDotsView()
        
        HStack {
            Text("Agent is thinking")
            ThinkingDotsView()
        }
    }
    .padding()
}

#Preview("Pulsing Dot") {
    VStack(spacing: 20) {
        PulsingDotView(color: .blue, size: 8)
        PulsingDotView(color: .green, size: 10)
        PulsingDotView(color: .orange, size: 12)
    }
    .padding()
}

#Preview("Typing Indicator") {
    VStack(spacing: 20) {
        TypingIndicatorView(agentName: "claude")
        TypingIndicatorView(agentName: "codex")
        TypingIndicatorView(agentName: nil)
    }
    .padding()
}

#Preview("Progress Spinner") {
    HStack(spacing: 20) {
        ProgressSpinnerView(size: 16, color: .blue)
        ProgressSpinnerView(size: 24, color: .green)
        ProgressSpinnerView(size: 32, lineWidth: 3, color: .orange)
    }
    .padding()
}

#Preview("Streaming Glow") {
    VStack(spacing: 20) {
        Text("This message is streaming...")
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .streamingGlow(isActive: true, color: .blue)
        
        Text("This message is complete")
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .streamingGlow(isActive: false)
    }
    .padding()
    .frame(width: 400)
}

#Preview("Agent Thinking") {
    VStack(spacing: 20) {
        AgentThinkingView(
            agentName: "claude",
            thought: nil,
            renderMarkdown: { AttributedString($0) }
        )
        
        AgentThinkingView(
            agentName: "claude",
            thought: "Analyzing the codebase structure and looking for relevant patterns...",
            renderMarkdown: { AttributedString($0) }
        )
    }
    .padding()
    .frame(width: 500)
}
