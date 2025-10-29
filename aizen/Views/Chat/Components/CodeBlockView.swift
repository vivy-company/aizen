//
//  CodeBlockView.swift
//  aizen
//
//  Code block rendering with syntax highlighting
//

import SwiftUI
import HighlightSwift

struct CodeBlockView: View {
    let code: String
    let language: String?

    @State private var showCopyConfirmation = false
    @State private var highlightedText: AttributedString?

    private let highlight = Highlight()

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
            .task(id: code) {
                await performHighlight()
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

    private func performHighlight() async {
        do {
            let attributed: AttributedString
            if let lang = language,
               !lang.isEmpty,
               let highlightLang = LanguageDetection.highlightLanguageFromFence(lang) {
                attributed = try await highlight.attributedText(
                    code,
                    language: highlightLang.rawValue,
                    colors: .dark(.github)
                )
            } else {
                attributed = try await highlight.attributedText(code)
            }
            highlightedText = attributed
        } catch {
            // Fallback to plain text on error
            highlightedText = AttributedString(code)
        }
    }
}
