//
//  CodeBlockView.swift
//  aizen
//
//  Code block rendering with syntax highlighting
//

import SwiftUI
import CodeEditSourceEditor
import CodeEditLanguages

struct CodeBlockView: View {
    let code: String
    let language: String?
    var isStreaming: Bool = false

    @State private var showCopyConfirmation = false
    @State private var highlightedText: AttributedString?
    @AppStorage("editorTheme") private var editorTheme: String = "Catppuccin Mocha"

    var body: some View {
      
        
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let lang = language, !lang.isEmpty {
                    Text(lang.uppercased())
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: copyCode) {
                    Image(systemName: showCopyConfirmation ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(String(localized: "chat.code.copy"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            
            ScrollView(.horizontal, showsIndicators: true) {
                Group  {
                    if let highlighted = highlightedText {
                        Text(highlighted)
                    } else {
                        Text(code)
                            .foregroundColor(.primary)
                    }
                }
                .font(.system(.body, design: .monospaced))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: true, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            .padding(8)
            .task(id: highlightTaskKey) {
                guard !isStreaming else { return }
                let snapshot = code
                await performHighlight(codeSnapshot: snapshot)
            }
         
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)

        withAnimation {
            showCopyConfirmation = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showCopyConfirmation = false
            }
        }
    }

    private var highlightTaskKey: String {
        "\(code.hashValue)-\(language ?? "none")-\(editorTheme)-\(isStreaming ? "stream" : "final")"
    }

    private func performHighlight(codeSnapshot: String) async {
        let detectedLanguage: CodeLanguage
        if let lang = language, !lang.isEmpty {
            detectedLanguage = LanguageDetection.languageFromFence(lang)
        } else {
            detectedLanguage = .default
        }

        // Load theme
        let theme = GhosttyThemeParser.loadTheme(named: editorTheme) ?? defaultTheme()

        // Use shared highlighting queue (limits concurrent highlighting, provides caching)
        if let attributed = await HighlightingQueue.shared.highlight(
            code: codeSnapshot,
            language: detectedLanguage,
            theme: theme
        ) {
            if codeSnapshot == code {
                highlightedText = attributed
            }
        } else {
            // Fallback to plain text on error or cancellation
            if highlightedText == nil, codeSnapshot == code {
                highlightedText = AttributedString(codeSnapshot)
            }
        }
    }

    private func defaultTheme() -> EditorTheme {
        let bg = NSColor(red: 0.12, green: 0.12, blue: 0.18, alpha: 1.0)
        let fg = NSColor(red: 0.8, green: 0.84, blue: 0.96, alpha: 1.0)

        return EditorTheme(
            text: .init(color: fg),
            insertionPoint: fg,
            invisibles: .init(color: .systemGray),
            background: bg,
            lineHighlight: bg.withAlphaComponent(0.05),
            selection: .selectedTextBackgroundColor,
            keywords: .init(color: .systemPurple),
            commands: .init(color: .systemBlue),
            types: .init(color: .systemYellow),
            attributes: .init(color: .systemRed),
            variables: .init(color: .systemCyan),
            values: .init(color: .systemOrange),
            numbers: .init(color: .systemOrange),
            strings: .init(color: .systemGreen),
            characters: .init(color: .systemGreen),
            comments: .init(color: .systemGray)
        )
    }
}
