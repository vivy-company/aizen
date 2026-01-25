//
//  OutputBlockView.swift
//  aizen
//
//  Reusable container for rich agent output blocks
//

import SwiftUI

struct OutputBlockView<Content: View>: View {
    let title: String
    let subtitle: String?
    let icon: String
    let accentColor: Color
    let status: ToolStatus?
    let isCollapsible: Bool
    let showAccentStripe: Bool
    @ViewBuilder let content: () -> Content
    
    @State private var isExpanded: Bool
    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme
    
    init(
        title: String,
        subtitle: String? = nil,
        icon: String = "circle",
        accentColor: Color = .secondary,
        status: ToolStatus? = nil,
        isCollapsible: Bool = true,
        showAccentStripe: Bool = true,
        initiallyExpanded: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.accentColor = accentColor
        self.status = status
        self.isCollapsible = isCollapsible
        self.showAccentStripe = showAccentStripe
        self._isExpanded = State(initialValue: initiallyExpanded)
        self.content = content
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
            
            if isExpanded {
                Divider()
                    .opacity(0.5)
                
                content()
                    .padding(OutputBlockTokens.contentPadding)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: OutputBlockTokens.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: OutputBlockTokens.cornerRadius)
                .stroke(borderColor, lineWidth: OutputBlockTokens.borderWidth)
        )
        .overlay(alignment: .leading) {
            if showAccentStripe {
                accentStripe
            }
        }
        .shadow(
            color: .black.opacity(colorScheme == .dark ? 0.3 : OutputBlockTokens.shadowOpacity),
            radius: isHovering ? OutputBlockTokens.shadowRadius + 2 : OutputBlockTokens.shadowRadius,
            x: 0,
            y: 2
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        Button(action: toggleExpand) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: OutputBlockTokens.iconSize, weight: .medium))
                    .foregroundStyle(accentColor)
                    .frame(width: OutputBlockTokens.iconSize + 2)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: OutputBlockTokens.titleFontSize, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: OutputBlockTokens.subtitleFontSize))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer(minLength: 8)
                
                if let status = status {
                    StatusBadgeView(status: status)
                }
                
                if isCollapsible {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, OutputBlockTokens.headerPaddingH)
            .padding(.vertical, OutputBlockTokens.headerPaddingV)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isCollapsible)
    }
    
    // MARK: - Accent Stripe
    
    private var accentStripe: some View {
        RoundedRectangle(cornerRadius: OutputBlockTokens.cornerRadius)
            .fill(accentColor)
            .frame(width: OutputBlockTokens.accentStripeWidth)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: OutputBlockTokens.cornerRadius,
                    bottomLeadingRadius: OutputBlockTokens.cornerRadius
                )
            )
    }
    
    // MARK: - Colors
    
    private var backgroundColor: Color {
        OutputBlockTokens.backgroundColor(for: colorScheme)
    }
    
    private var borderColor: Color {
        OutputBlockTokens.borderColor(for: colorScheme)
    }
    
    // MARK: - Actions
    
    private func toggleExpand() {
        guard isCollapsible else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            isExpanded.toggle()
        }
    }
}

// MARK: - Status Badge

struct StatusBadgeView: View {
    let status: ToolStatus
    
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 4) {
            statusIcon
            
            Text(status.displayLabel)
                .font(.system(size: 10, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(status.backgroundColor)
        .foregroundStyle(status.accentColor)
        .clipShape(Capsule())
        .onAppear {
            if status == .inProgress {
                withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }
        }
        .onChange(of: status) { _, newStatus in
            if newStatus == .inProgress {
                withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            } else {
                isAnimating = false
            }
        }
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        if status == .inProgress {
            Image(systemName: status.iconName)
                .font(.system(size: 10, weight: .semibold))
                .opacity(isAnimating ? 0.5 : 1.0)
                .rotationEffect(.degrees(isAnimating ? 360 : 0))
                .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isAnimating)
        } else {
            Image(systemName: status.iconName)
                .font(.system(size: 10, weight: .semibold))
        }
    }
}

// MARK: - Compact Status Badge

/// A minimal status indicator for inline use in tool call headers
struct CompactStatusBadge: View {
    let status: ToolStatus
    
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 3) {
            statusIcon
            
            if status == .inProgress {
                Text("Running")
                    .font(.system(size: 9, weight: .medium))
            }
        }
        .foregroundStyle(status.accentColor)
        .onAppear {
            if status == .inProgress {
                withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }
        }
        .onChange(of: status) { _, newStatus in
            if newStatus == .inProgress {
                withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            } else {
                isAnimating = false
            }
        }
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case .inProgress:
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 10, height: 10)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10, weight: .semibold))
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 10, weight: .semibold))
        case .pending:
            Image(systemName: "circle")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Convenience Initializers

extension OutputBlockView {
    init(
        toolKind: ToolKind,
        title: String,
        subtitle: String? = nil,
        status: ToolStatus? = nil,
        initiallyExpanded: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            icon: toolKind.symbolName,
            accentColor: toolKind.accentColor,
            status: status,
            isCollapsible: true,
            showAccentStripe: true,
            initiallyExpanded: initiallyExpanded,
            content: content
        )
    }
    
    init(
        blockType: OutputBlockType,
        title: String,
        subtitle: String? = nil,
        initiallyExpanded: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            icon: blockType.iconName,
            accentColor: blockType.accentColor,
            status: nil,
            isCollapsible: true,
            showAccentStripe: true,
            initiallyExpanded: initiallyExpanded,
            content: content
        )
    }
}

// MARK: - Preview

#Preview("Tool Call Block") {
    VStack(spacing: 16) {
        OutputBlockView(
            toolKind: .read,
            title: "src/components/Button.tsx",
            subtitle: "Reading file contents",
            status: .completed,
            initiallyExpanded: true
        ) {
            Text("File contents would appear here...")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        
        OutputBlockView(
            toolKind: .execute,
            title: "npm run build",
            status: .inProgress
        ) {
            Text("Build output streaming...")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        
        OutputBlockView(
            toolKind: .edit,
            title: "src/utils/helpers.ts",
            subtitle: "Modifying function signature",
            status: .failed
        ) {
            Text("Error: File not found")
                .font(.system(size: 12))
                .foregroundStyle(.red)
        }
    }
    .padding()
    .frame(width: 500)
}

#Preview("Semantic Blocks") {
    VStack(spacing: 16) {
        OutputBlockView(
            blockType: .info,
            title: "Information"
        ) {
            Text("This is an informational message with helpful context.")
                .font(.system(size: 12))
        }
        
        OutputBlockView(
            blockType: .success,
            title: "Success"
        ) {
            Text("Operation completed successfully!")
                .font(.system(size: 12))
        }
        
        OutputBlockView(
            blockType: .warning,
            title: "Warning"
        ) {
            Text("This action may have unintended consequences.")
                .font(.system(size: 12))
        }
        
        OutputBlockView(
            blockType: .error,
            title: "Error"
        ) {
            Text("Failed to complete the operation. Please try again.")
                .font(.system(size: 12))
        }
    }
    .padding()
    .frame(width: 500)
}
