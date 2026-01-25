//
//  CollapsibleSection.swift
//  aizen
//
//  Reusable collapsible section component with smooth animations
//

import SwiftUI

struct CollapsibleSection<Header: View, Content: View, Summary: View>: View {
    let header: Header
    let content: Content
    let summary: Summary?
    let initiallyExpanded: Bool
    let accentColor: Color
    let showChevron: Bool
    let animationDuration: Double
    
    @State private var isExpanded: Bool
    @State private var isHovering: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    
    init(
        initiallyExpanded: Bool = false,
        accentColor: Color = .accentColor,
        showChevron: Bool = true,
        animationDuration: Double = 0.2,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content,
        @ViewBuilder summary: () -> Summary
    ) {
        self.header = header()
        self.content = content()
        self.summary = summary()
        self.initiallyExpanded = initiallyExpanded
        self.accentColor = accentColor
        self.showChevron = showChevron
        self.animationDuration = animationDuration
        self._isExpanded = State(initialValue: initiallyExpanded)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerButton
            
            if isExpanded {
                content
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: animationDuration), value: isExpanded)
    }
    
    private var headerButton: some View {
        Button(action: toggle) {
            HStack(spacing: 8) {
                if showChevron {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                }
                
                header
                
                Spacer()
                
                if !isExpanded, let summary = summary {
                    summary
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    private func toggle() {
        withAnimation(.easeInOut(duration: animationDuration)) {
            isExpanded.toggle()
        }
    }
}

extension CollapsibleSection where Summary == EmptyView {
    init(
        initiallyExpanded: Bool = false,
        accentColor: Color = .accentColor,
        showChevron: Bool = true,
        animationDuration: Double = 0.2,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) {
        self.header = header()
        self.content = content()
        self.summary = nil
        self.initiallyExpanded = initiallyExpanded
        self.accentColor = accentColor
        self.showChevron = showChevron
        self.animationDuration = animationDuration
        self._isExpanded = State(initialValue: initiallyExpanded)
    }
}

// MARK: - Styled Collapsible Section

struct StyledCollapsibleSection<Header: View, Content: View, Summary: View>: View {
    let header: Header
    let content: Content
    let summary: Summary?
    let initiallyExpanded: Bool
    let accentColor: Color
    let style: SectionStyle
    
    @State private var isExpanded: Bool
    @State private var isHovering: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    
    enum SectionStyle {
        case plain
        case card
        case bordered
        case accented
    }
    
    init(
        initiallyExpanded: Bool = false,
        accentColor: Color = .accentColor,
        style: SectionStyle = .plain,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content,
        @ViewBuilder summary: () -> Summary
    ) {
        self.header = header()
        self.content = content()
        self.summary = summary()
        self.initiallyExpanded = initiallyExpanded
        self.accentColor = accentColor
        self.style = style
        self._isExpanded = State(initialValue: initiallyExpanded)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerButton
            
            if isExpanded {
                if style != .plain {
                    Divider()
                        .opacity(0.5)
                }
                
                content
                    .padding(.horizontal, style == .plain ? 0 : 12)
                    .padding(.vertical, style == .plain ? 4 : 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(borderColor, lineWidth: borderWidth)
        )
        .overlay(alignment: .leading) {
            if style == .accented {
                UnevenRoundedRectangle(topLeadingRadius: cornerRadius, bottomLeadingRadius: cornerRadius)
                    .fill(accentColor)
                    .frame(width: 3)
            }
        }
        .shadow(
            color: shadowColor,
            radius: isHovering ? 4 : 2,
            x: 0,
            y: 1
        )
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
    }
    
    private var headerButton: some View {
        Button(action: toggle) {
            HStack(spacing: 8) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
                
                header
                
                Spacer()
                
                if !isExpanded, let summary = summary {
                    summary
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, style == .plain ? 0 : 12)
            .padding(.vertical, style == .plain ? 6 : 10)
            .background(headerBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    private func toggle() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isExpanded.toggle()
        }
    }
    
    private var backgroundColor: Color {
        switch style {
        case .plain: return .clear
        case .card, .bordered, .accented:
            return colorScheme == .dark
                ? Color(.controlBackgroundColor).opacity(0.3)
                : Color(.controlBackgroundColor).opacity(0.5)
        }
    }
    
    private var headerBackground: Color {
        switch style {
        case .plain: return .clear
        case .card, .accented:
            return colorScheme == .dark
                ? Color.white.opacity(0.03)
                : Color.black.opacity(0.02)
        case .bordered: return .clear
        }
    }
    
    private var borderColor: Color {
        switch style {
        case .plain: return .clear
        case .card: return .clear
        case .bordered, .accented:
            return colorScheme == .dark
                ? Color.white.opacity(0.1)
                : Color.black.opacity(0.1)
        }
    }
    
    private var borderWidth: CGFloat {
        style == .bordered || style == .accented ? 1 : 0
    }
    
    private var cornerRadius: CGFloat {
        style == .plain ? 0 : 8
    }
    
    private var shadowColor: Color {
        switch style {
        case .plain, .bordered: return .clear
        case .card, .accented:
            return colorScheme == .dark
                ? Color.black.opacity(0.2)
                : Color.black.opacity(0.06)
        }
    }
}

extension StyledCollapsibleSection where Summary == EmptyView {
    init(
        initiallyExpanded: Bool = false,
        accentColor: Color = .accentColor,
        style: SectionStyle = .plain,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) {
        self.header = header()
        self.content = content()
        self.summary = nil
        self.initiallyExpanded = initiallyExpanded
        self.accentColor = accentColor
        self.style = style
        self._isExpanded = State(initialValue: initiallyExpanded)
    }
}

// MARK: - Previews

#Preview("Collapsible Sections") {
    ScrollView {
        VStack(spacing: 16) {
            StyledCollapsibleSection(
                initiallyExpanded: true,
                accentColor: .blue,
                style: .accented
            ) {
                Label("File Operations", systemImage: "doc.fill")
                    .font(.system(size: 12, weight: .medium))
            } content: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Created: main.swift")
                    Text("Modified: Package.swift")
                    Text("Deleted: old.swift")
                }
                .font(.system(size: 11))
            } summary: {
                Text("3 files")
            }
            
            StyledCollapsibleSection(
                initiallyExpanded: false,
                accentColor: .green,
                style: .card
            ) {
                Label("Terminal Output", systemImage: "terminal.fill")
                    .font(.system(size: 12, weight: .medium))
            } content: {
                Text("npm install completed successfully")
                    .font(.system(size: 11, design: .monospaced))
            } summary: {
                Text("Success")
                    .foregroundStyle(.green)
            }
            
            StyledCollapsibleSection(
                initiallyExpanded: false,
                style: .bordered
            ) {
                Text("More Details")
                    .font(.system(size: 12, weight: .medium))
            } content: {
                Text("This is some additional content that can be expanded.")
                    .font(.system(size: 11))
            } summary: {
                Text("Click to expand")
            }
            
            CollapsibleSection(initiallyExpanded: true) {
                Text("Plain Section")
                    .font(.system(size: 12, weight: .medium))
            } content: {
                Text("Plain style without decorations")
                    .font(.system(size: 11))
            } summary: {
                Text("...")
            }
        }
        .padding()
    }
    .frame(width: 400, height: 500)
}
