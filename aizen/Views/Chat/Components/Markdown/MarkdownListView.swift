//  MarkdownListView.swift
//  aizen
//
//  Math block rendering using KaTeX and WebKit
//

import SwiftUI
import WebKit

// MARK: - KaTeX Resource Manager

/// Manages KaTeX resources in a temp directory for WebKit access
class KaTeXResourceManager {
    static let shared = KaTeXResourceManager()

    private(set) var tempDir: URL?
    private var isSetup = false

    private init() {
        setupTempDirectory()
    }

    private func setupTempDirectory() {
        guard !isSetup else { return }
        isSetup = true

        let fileManager = FileManager.default
        let tempPath = fileManager.temporaryDirectory.appendingPathComponent("aizen-katex", isDirectory: true)

        do {
            try fileManager.createDirectory(at: tempPath, withIntermediateDirectories: true)

            // Copy katex.min.js from bundle
            if let jsURL = Bundle.main.url(forResource: "katex.min", withExtension: "js", subdirectory: "katex") {
                let destURL = tempPath.appendingPathComponent("katex.min.js")
                if !fileManager.fileExists(atPath: destURL.path) {
                    try fileManager.copyItem(at: jsURL, to: destURL)
                }
            }

            // Copy katex.min.css from bundle
            if let cssURL = Bundle.main.url(forResource: "katex.min", withExtension: "css", subdirectory: "katex") {
                let destURL = tempPath.appendingPathComponent("katex.min.css")
                if !fileManager.fileExists(atPath: destURL.path) {
                    try fileManager.copyItem(at: cssURL, to: destURL)
                }
            }

            // Copy font files
            let fontsDir = tempPath.appendingPathComponent("fonts")
            if !fileManager.fileExists(atPath: fontsDir.path) {
                try fileManager.createDirectory(at: fontsDir, withIntermediateDirectories: true)
            }

            // Copy KaTeX fonts from bundle's fonts directory
            if let resourcePath = Bundle.main.resourcePath {
                let fontsSrcDir = URL(fileURLWithPath: resourcePath).appendingPathComponent("fonts")
                if let files = try? fileManager.contentsOfDirectory(at: fontsSrcDir, includingPropertiesForKeys: nil) {
                    for file in files where file.lastPathComponent.hasPrefix("KaTeX_") {
                        let destFile = fontsDir.appendingPathComponent(file.lastPathComponent)
                        if !fileManager.fileExists(atPath: destFile.path) {
                            try? fileManager.copyItem(at: file, to: destFile)
                        }
                    }
                }
            }

            self.tempDir = tempPath
        } catch {
            print("Failed to setup KaTeX temp directory: \(error)")
        }
    }
}

// MARK: - Math Block View

struct MathBlockView: View {
    let content: String
    var isBlock: Bool = true

    @State private var webViewHeight: CGFloat = 60
    @State private var isLoading = true
    @State private var hasError = false
    @State private var errorMessage: String?
    @Environment(\.colorScheme) private var colorScheme

    private var headerBackground: Color {
        CodeBlockColors.headerBackground(for: colorScheme)
    }

    private var contentBackground: Color {
        CodeBlockColors.contentBackground(for: colorScheme)
    }

    var body: some View {
        if isBlock {
            // Block math with container
            VStack(alignment: .leading, spacing: 0) {
                // Header
                CodeBlockHeader(
                    iconSystemName: "function",
                    title: "LATEX",
                    showsLoading: isLoading,
                    hasError: hasError,
                    errorMessage: errorMessage,
                    copyHelpText: "Copy LaTeX",
                    isHovered: false,
                    headerBackground: headerBackground,
                    onCopy: copyLatex
                )

                // Content
                Group {
                    if hasError {
                        // Show code on error
                        codeView
                    } else {
                        KaTeXWebView(
                            content: content,
                            isBlock: true,
                            isDark: colorScheme == .dark,
                            height: $webViewHeight,
                            isLoading: $isLoading,
                            hasError: $hasError,
                            errorMessage: $errorMessage
                        )
                        .frame(height: webViewHeight)
                    }
                }
                .background(contentBackground)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 4, x: 0, y: 2)
        } else {
            // Inline math
            KaTeXWebView(
                content: content,
                isBlock: false,
                isDark: colorScheme == .dark,
                height: $webViewHeight,
                isLoading: $isLoading,
                hasError: $hasError,
                errorMessage: $errorMessage
            )
            .frame(height: webViewHeight)
        }
    }

    private var codeView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(content)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
    }

    private func copyLatex() {
        Clipboard.copy(content)
    }
}

// MARK: - Non-Scrolling WKWebView for KaTeX

class KaTeXNonScrollingWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }
}

// MARK: - KaTeX Web View

struct KaTeXWebView: NSViewRepresentable {
    let content: String
    let isBlock: Bool
    let isDark: Bool
    @Binding var height: CGFloat
    @Binding var isLoading: Bool
    @Binding var hasError: Bool
    @Binding var errorMessage: String?

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "katexResult")
        contentController.add(context.coordinator, name: "katexError")
        config.userContentController = contentController

        let webView = KaTeXNonScrollingWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")

        context.coordinator.webView = webView
        context.coordinator.loadContent(content: content, isBlock: isBlock, isDark: isDark)

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastContent != content || context.coordinator.lastIsDark != isDark {
            context.coordinator.lastContent = content
            context.coordinator.lastIsDark = isDark
            context.coordinator.loadContent(content: content, isBlock: isBlock, isDark: isDark)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: KaTeXWebView
        weak var webView: WKWebView?
        var lastContent: String = ""
        var lastIsDark: Bool = false

        init(_ parent: KaTeXWebView) {
            self.parent = parent
        }

        func loadContent(content: String, isBlock: Bool, isDark: Bool) {
            guard let webView = webView else { return }
            guard let tempDir = KaTeXResourceManager.shared.tempDir else {
                DispatchQueue.main.async {
                    self.parent.hasError = true
                    self.parent.errorMessage = "Failed to setup KaTeX resources"
                    self.parent.isLoading = false
                }
                return
            }

            let escapedContent = content
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "")

            let bgColor = "transparent"
            let textColor = isDark ? "#e0e0e0" : "#1a1a1a"

            let html = """
            <!DOCTYPE html>
            <html>
            <head>
                <meta charset="UTF-8">
                <link rel="stylesheet" href="katex.min.css">
                <script src="katex.min.js"></script>
                <style>
                    * { margin: 0; padding: 0; box-sizing: border-box; }
                    html, body {
                        background: \(bgColor);
                        overflow: hidden;
                    }
                    body {
                        padding: 12px;
                        display: flex;
                        justify-content: center;
                        align-items: center;
                    }
                    #math {
                        color: \(textColor);
                        font-size: \(isBlock ? "1.3em" : "1em");
                    }
                    .katex { color: \(textColor) !important; }
                    .katex .mord { color: \(textColor) !important; }
                    .katex .mbin { color: \(textColor) !important; }
                    .katex .mrel { color: \(textColor) !important; }
                    .katex .mop { color: \(textColor) !important; }
                </style>
            </head>
            <body>
                <div id="math"></div>
                <script>
                    function init() {
                        if (typeof katex === 'undefined') {
                            setTimeout(init, 50);
                            return;
                        }

                        try {
                            katex.render('\(escapedContent)', document.getElementById('math'), {
                                displayMode: \(isBlock),
                                throwOnError: false,
                                strict: false
                            });

                            // Wait for fonts then report height
                            if (document.fonts && document.fonts.ready) {
                                document.fonts.ready.then(reportSize);
                            } else {
                                setTimeout(reportSize, 200);
                            }
                        } catch (e) {
                            window.webkit.messageHandlers.katexError.postMessage(e.message || String(e));
                        }
                    }

                    function reportSize() {
                        requestAnimationFrame(function() {
                            const el = document.getElementById('math');
                            const height = el.offsetHeight + 24;
                            window.webkit.messageHandlers.katexResult.postMessage({ height: height });
                        });
                    }

                    init();
                </script>
            </body>
            </html>
            """

            // Write HTML to temp file and use loadFileURL
            let htmlFile = tempDir.appendingPathComponent("math-\(UUID().uuidString).html")
            do {
                try html.write(to: htmlFile, atomically: true, encoding: .utf8)
                webView.loadFileURL(htmlFile, allowingReadAccessTo: tempDir)
            } catch {
                DispatchQueue.main.async {
                    self.parent.hasError = true
                    self.parent.errorMessage = "Failed to write HTML: \(error.localizedDescription)"
                    self.parent.isLoading = false
                }
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            DispatchQueue.main.async {
                if message.name == "katexResult", let body = message.body as? [String: Any] {
                    if let height = body["height"] as? CGFloat {
                        self.parent.height = max(height, 40)
                    }
                    self.parent.isLoading = false
                    self.parent.hasError = false
                    self.parent.errorMessage = nil
                } else if message.name == "katexError" {
                    let msg = message.body as? String ?? "Unknown error"
                    self.parent.isLoading = false
                    self.parent.hasError = true
                    self.parent.errorMessage = msg
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Navigation finished
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.hasError = true
                self.parent.errorMessage = error.localizedDescription
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.hasError = true
                self.parent.errorMessage = error.localizedDescription
            }
        }
    }
}
