//
//  FilePreviewSnippetView.swift
//  aizen
//
//  Compact file preview showing relevant lines with syntax highlighting
//

import SwiftUI

struct FilePreviewSnippetView: View {
    let filePath: String
    let content: String?
    let startLine: Int
    let highlightLines: Set<Int>
    var maxLines: Int = 10
    var onOpen: ((String) -> Void)?
    
    @AppStorage("terminalFontName") private var fontName = "Menlo"
    @AppStorage("terminalFontSize") private var fontSize = 12.0
    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme
    
    private var effectiveFontSize: CGFloat {
        max(fontSize - 2, 9)
    }
    
    private var fileName: String {
        URL(fileURLWithPath: filePath).lastPathComponent
    }
    
    private var fileExtension: String {
        URL(fileURLWithPath: filePath).pathExtension
    }
    
    private var directoryPath: String {
        let dir = (filePath as NSString).deletingLastPathComponent
        let components = dir.components(separatedBy: "/")
        if components.count > 3 {
            return ".../" + components.suffix(2).joined(separator: "/")
        }
        return dir
    }
    
    private var lines: [(number: Int, content: String)] {
        guard let content = content else { return [] }
        let allLines = content.components(separatedBy: "\n")
        let endLine = min(startLine + maxLines - 1, allLines.count)
        let adjustedStart = max(1, startLine)
        
        var result: [(Int, String)] = []
        for lineNum in adjustedStart...endLine {
            let index = lineNum - 1
            if index < allLines.count {
                result.append((lineNum, allLines[index]))
            }
        }
        return result
    }
    
    private var lineNumberWidth: CGFloat {
        let maxLineNum = lines.last?.number ?? 1
        let digits = String(maxLineNum).count
        return CGFloat(digits * 8 + 16)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
            
            if content != nil {
                Divider()
                    .opacity(0.5)
                
                contentView
            } else {
                emptyContentView
            }
        }
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(borderColor, lineWidth: 0.5)
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    private var headerView: some View {
        HStack(spacing: 6) {
            fileIcon
            
            VStack(alignment: .leading, spacing: 1) {
                Text(fileName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                if !directoryPath.isEmpty {
                    Text(directoryPath)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            if startLine > 1 || lines.count < (content?.components(separatedBy: "\n").count ?? 0) {
                Text("L\(startLine)-\(startLine + lines.count - 1)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            
            if let onOpen = onOpen {
                Button {
                    onOpen(filePath)
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(isHovering ? 1 : 0.5)
                .help("Open in editor")
            }
            
            CopyButton(text: content ?? "", iconSize: 10)
                .opacity(isHovering ? 1 : 0.5)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(headerBackground)
    }
    
    private var fileIcon: some View {
        Image(systemName: iconName)
            .font(.system(size: 12))
            .foregroundStyle(iconColor)
            .frame(width: 16, height: 16)
    }
    
    private var iconName: String {
        switch fileExtension.lowercased() {
        case "swift": return "swift"
        case "js", "jsx", "ts", "tsx": return "j.square.fill"
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "rb": return "diamond.fill"
        case "go": return "g.square.fill"
        case "rs": return "gearshape.fill"
        case "md", "markdown": return "doc.richtext"
        case "json", "yaml", "yml", "toml": return "doc.badge.gearshape"
        case "html", "css", "scss": return "globe"
        case "sh", "bash", "zsh": return "terminal.fill"
        default: return "doc.fill"
        }
    }
    
    private var iconColor: Color {
        switch fileExtension.lowercased() {
        case "swift": return .orange
        case "js", "jsx": return .yellow
        case "ts", "tsx": return .blue
        case "py": return .green
        case "rb": return .red
        case "go": return .cyan
        case "rs": return .orange
        case "md", "markdown": return .purple
        case "json", "yaml", "yml", "toml": return .gray
        case "html": return .orange
        case "css", "scss": return .blue
        default: return .secondary
        }
    }
    
    private var contentView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(lines, id: \.number) { line in
                    HStack(alignment: .top, spacing: 0) {
                        Text("\(line.number)")
                            .font(.system(size: effectiveFontSize, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .frame(width: lineNumberWidth, alignment: .trailing)
                            .padding(.trailing, 8)
                        
                        Text(line.content)
                            .font(.custom(fontName, size: effectiveFontSize))
                            .foregroundStyle(highlightLines.contains(line.number) ? .primary : .secondary)
                    }
                    .padding(.vertical, 1)
                    .background(
                        highlightLines.contains(line.number)
                            ? highlightColor
                            : Color.clear
                    )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(maxHeight: 200)
    }
    
    private var emptyContentView: some View {
        HStack {
            Spacer()
            Text("No content available")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Styling
    
    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color(.controlBackgroundColor).opacity(0.3)
            : Color(.controlBackgroundColor).opacity(0.5)
    }
    
    private var headerBackground: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.03)
            : Color.black.opacity(0.02)
    }
    
    private var borderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.1)
            : Color.black.opacity(0.1)
    }
    
    private var highlightColor: Color {
        colorScheme == .dark
            ? Color.yellow.opacity(0.1)
            : Color.yellow.opacity(0.15)
    }
}

// MARK: - Convenience Initializers

extension FilePreviewSnippetView {
    init(filePath: String, content: String?, onOpen: ((String) -> Void)? = nil) {
        self.filePath = filePath
        self.content = content
        self.startLine = 1
        self.highlightLines = []
        self.onOpen = onOpen
    }
    
    init(filePath: String, lines: [String], startLine: Int = 1, highlightLines: Set<Int> = [], onOpen: ((String) -> Void)? = nil) {
        self.filePath = filePath
        self.content = lines.joined(separator: "\n")
        self.startLine = startLine
        self.highlightLines = highlightLines
        self.onOpen = onOpen
    }
}

// MARK: - File Snippet from Diff

struct DiffFileSnippetView: View {
    let diff: ToolCallDiff
    var maxLines: Int = 8
    var onOpen: ((String) -> Void)?
    
    @AppStorage("terminalFontName") private var fontName = "Menlo"
    @AppStorage("terminalFontSize") private var fontSize = 12.0
    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme
    
    private var effectiveFontSize: CGFloat {
        max(fontSize - 2, 9)
    }
    
    private var fileName: String {
        URL(fileURLWithPath: diff.path).lastPathComponent
    }
    
    private var isNewFile: Bool {
        diff.oldText == nil || diff.oldText?.isEmpty == true
    }
    
    private var previewLines: [(type: LineType, content: String)] {
        let newLines = diff.newText.components(separatedBy: "\n")
        let oldLines = diff.oldText?.components(separatedBy: "\n") ?? []
        
        if isNewFile {
            return Array(newLines.prefix(maxLines)).map { (.added, $0) }
        }
        
        var result: [(LineType, String)] = []
        let linesToShow = min(maxLines, max(newLines.count, oldLines.count))
        
        for i in 0..<linesToShow {
            let newLine = i < newLines.count ? newLines[i] : nil
            let oldLine = i < oldLines.count ? oldLines[i] : nil
            
            if newLine == oldLine {
                if let line = newLine {
                    result.append((.unchanged, line))
                }
            } else {
                if let old = oldLine, !old.isEmpty {
                    result.append((.removed, old))
                }
                if let new = newLine {
                    result.append((.added, new))
                }
            }
        }
        
        return result
    }
    
    enum LineType {
        case added, removed, unchanged
        
        var color: Color {
            switch self {
            case .added: return .green
            case .removed: return .red
            case .unchanged: return .secondary
            }
        }
        
        var prefix: String {
            switch self {
            case .added: return "+"
            case .removed: return "-"
            case .unchanged: return " "
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
            
            Divider()
                .opacity(0.5)
            
            contentView
        }
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(borderColor, lineWidth: 0.5)
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    private var headerView: some View {
        HStack(spacing: 6) {
            Image(systemName: isNewFile ? "doc.badge.plus" : "doc.badge.ellipsis")
                .font(.system(size: 11))
                .foregroundStyle(isNewFile ? .green : .orange)
            
            Text(fileName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            
            Spacer()
            
            if let onOpen = onOpen {
                Button {
                    onOpen(diff.path)
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(isHovering ? 1 : 0.5)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(headerBackground)
    }
    
    private var contentView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(previewLines.enumerated()), id: \.offset) { index, line in
                    HStack(alignment: .top, spacing: 0) {
                        Text(line.type.prefix)
                            .font(.system(size: effectiveFontSize, weight: .medium, design: .monospaced))
                            .foregroundStyle(line.type.color)
                            .frame(width: 16)
                        
                        Text(line.content)
                            .font(.custom(fontName, size: effectiveFontSize))
                            .foregroundStyle(line.type == .unchanged ? .secondary : .primary)
                    }
                    .padding(.vertical, 1)
                    .background(lineBackground(for: line.type))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(maxHeight: 150)
    }
    
    private func lineBackground(for type: LineType) -> Color {
        switch type {
        case .added:
            return colorScheme == .dark
                ? Color.green.opacity(0.1)
                : Color.green.opacity(0.1)
        case .removed:
            return colorScheme == .dark
                ? Color.red.opacity(0.1)
                : Color.red.opacity(0.1)
        case .unchanged:
            return .clear
        }
    }
    
    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color(.controlBackgroundColor).opacity(0.3)
            : Color(.controlBackgroundColor).opacity(0.5)
    }
    
    private var headerBackground: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.03)
            : Color.black.opacity(0.02)
    }
    
    private var borderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.1)
            : Color.black.opacity(0.1)
    }
}

// MARK: - Previews

#Preview("File Preview Snippets") {
    ScrollView {
        VStack(spacing: 16) {
            FilePreviewSnippetView(
                filePath: "/Users/dev/project/src/main.swift",
                content: """
                import Foundation
                
                func main() {
                    print("Hello, World!")
                    let config = loadConfig()
                    startServer(config: config)
                }
                
                main()
                """,
                startLine: 1,
                highlightLines: [4, 5, 6],
                onOpen: { _ in }
            )
            
            FilePreviewSnippetView(
                filePath: "/Users/dev/project/package.json",
                content: """
                {
                  "name": "my-project",
                  "version": "1.0.0",
                  "dependencies": {
                    "express": "^4.18.0"
                  }
                }
                """,
                onOpen: { _ in }
            )
            
            FilePreviewSnippetView(
                filePath: "/Users/dev/project/empty.txt",
                content: nil,
                startLine: 1,
                highlightLines: []
            )
        }
        .padding()
    }
    .frame(width: 500, height: 600)
}
