//
//  RichTerminalOutputView.swift
//  aizen
//

import SwiftUI

struct RichTerminalOutputView: View {
    let output: String
    var maxLines: Int = 50
    var fontSize: CGFloat = 11
    var showLineNumbers: Bool = false
    
    @AppStorage("terminalThemeName") private var themeName = "Aizen Dark"
    @State private var isExpanded = false
    @State private var isHovering = false
    
    private var theme: TerminalThemeProvider {
        TerminalThemeProvider(themeName: themeName)
    }
    
    private var lines: [String] {
        output.components(separatedBy: "\n")
    }
    
    private var totalLineCount: Int {
        lines.count
    }
    
    private var isTruncated: Bool {
        !isExpanded && totalLineCount > maxLines
    }
    
    private var visibleLines: [String] {
        if isExpanded || totalLineCount <= maxLines {
            return lines
        }
        let headCount = maxLines / 2
        let tailCount = maxLines - headCount
        let head = Array(lines.prefix(headCount))
        let tail = Array(lines.suffix(tailCount))
        return head + [""] + tail
    }
    
    private var hiddenLineCount: Int {
        max(0, totalLineCount - maxLines)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(visibleLines.enumerated()), id: \.offset) { index, line in
                        if isTruncated && index == maxLines / 2 {
                            truncationIndicator
                        } else {
                            lineView(line, lineNumber: actualLineNumber(for: index))
                        }
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: isExpanded ? 400 : 200)
            .background(theme.background)
            
            if totalLineCount > 10 || isTruncated {
                footer
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(theme.borderColor, lineWidth: 1)
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    private func lineView(_ line: String, lineNumber: Int) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if showLineNumbers {
                Text("\(lineNumber)")
                    .font(.system(size: fontSize, design: .monospaced))
                    .foregroundStyle(theme.ansiMuted)
                    .frame(minWidth: 30, alignment: .trailing)
            }
            
            Text(ANSIParser.parse(line.isEmpty ? " " : line))
                .font(.system(size: fontSize, design: .monospaced))
                .foregroundStyle(theme.foreground)
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func actualLineNumber(for index: Int) -> Int {
        if !isTruncated || index < maxLines / 2 {
            return index + 1
        }
        let headCount = maxLines / 2
        let tailStart = totalLineCount - (maxLines - headCount)
        return tailStart + (index - headCount)
    }
    
    private var truncationIndicator: some View {
        HStack(spacing: 8) {
            Image(systemName: "ellipsis")
                .font(.system(size: 10))
            Text("\(hiddenLineCount) lines hidden")
                .font(.system(size: 10))
            Button("Show all") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded = true
                }
            }
            .font(.system(size: 10, weight: .medium))
            .buttonStyle(.plain)
        }
        .foregroundStyle(theme.ansiMuted)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(theme.background.opacity(0.5))
    }
    
    private var footer: some View {
        HStack {
            Text("\(totalLineCount) lines")
                .font(.system(size: 10))
                .foregroundStyle(theme.ansiMuted)
            
            Spacer()
            
            if isTruncated {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded = true
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.left.and.arrow.up.right")
                            .font(.system(size: 9))
                        Text("Expand")
                            .font(.system(size: 10, weight: .medium))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.ansiBlue)
            } else if isExpanded && totalLineCount > maxLines {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.and.arrow.down.left")
                            .font(.system(size: 9))
                        Text("Collapse")
                            .font(.system(size: 10, weight: .medium))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.ansiBlue)
            }
            
            Button {
                Clipboard.copy(output)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.ansiMuted)
            .opacity(isHovering ? 1 : 0.5)
            .help("Copy output")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.headerBackground)
    }
}

#Preview("Short Output") {
    RichTerminalOutputView(
        output: """
        $ npm run build
        > project@1.0.0 build
        > tsc && vite build
        
        vite v5.0.0 building for production...
        ✓ 142 modules transformed.
        dist/index.html              0.45 kB
        dist/assets/index.js        142.54 kB
        ✓ built in 1.24s
        """
    )
    .frame(width: 500)
    .padding()
}

#Preview("Long Output") {
    RichTerminalOutputView(
        output: (1...100).map { "Line \($0): Some output text here with more content" }.joined(separator: "\n"),
        showLineNumbers: true
    )
    .frame(width: 500)
    .padding()
}
