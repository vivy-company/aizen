//  MermaidDiagramView.swift
//  aizen
//
//  Mermaid diagram rendering using local WKWebView with bundled mermaid.js
//

import SwiftUI
import WebKit

// MARK: - Mermaid Resource Manager

/// Manages mermaid.js resources in a temp directory for WebKit access
class MermaidResourceManager {
    static let shared = MermaidResourceManager()

    private(set) var tempDir: URL?
    private var isSetup = false

    private init() {
        setupTempDirectory()
    }

    private func setupTempDirectory() {
        guard !isSetup else { return }
        isSetup = true

        let fileManager = FileManager.default
        let tempPath = fileManager.temporaryDirectory.appendingPathComponent("aizen-mermaid", isDirectory: true)

        do {
            try fileManager.createDirectory(at: tempPath, withIntermediateDirectories: true)

            // Copy mermaid.min.js from bundle
            if let jsURL = Bundle.main.url(forResource: "mermaid.min", withExtension: "js", subdirectory: "mermaid") {
                let destURL = tempPath.appendingPathComponent("mermaid.min.js")
                if !fileManager.fileExists(atPath: destURL.path) {
                    try fileManager.copyItem(at: jsURL, to: destURL)
                }
            }

            self.tempDir = tempPath
        } catch {
            print("Failed to setup mermaid temp directory: \(error)")
        }
    }
}

// MARK: - Mermaid Diagram View

struct MermaidDiagramView: View {
    let code: String
    var isStreaming: Bool = false

    @State private var webViewHeight: CGFloat = 200
    @State private var isLoading = true
    @State private var hasError = false
    @State private var errorMessage: String?
    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme

    private var headerBackground: Color {
        CodeBlockColors.headerBackground()
    }

    private var contentBackground: Color {
        CodeBlockColors.contentBackground()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            CodeBlockHeader(
                iconSystemName: "chart.bar.doc.horizontal",
                title: "MERMAID",
                showsLoading: isLoading && !isStreaming,
                hasError: hasError,
                errorMessage: errorMessage,
                copyHelpText: "Copy Mermaid code",
                isHovered: isHovering,
                headerBackground: headerBackground,
                onCopy: copyCode
            )

            // Content
            Group {
                if !isStreaming && !code.isEmpty {
                    if hasError {
                        // Show code on error
                        codeView
                    } else {
                        MermaidWebView(
                            code: code,
                            isDark: colorScheme == .dark,
                            height: $webViewHeight,
                            isLoading: $isLoading,
                            hasError: $hasError,
                            errorMessage: $errorMessage
                        )
                        .frame(height: webViewHeight)
                    }
                } else {
                    codeView
                }
            }
            .background(contentBackground)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 4, x: 0, y: 2)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }

    private var codeView: some View {
        ScrollView([.horizontal, .vertical], showsIndicators: true) {
            Text(code)
                .font(.system(size: 13, design: .monospaced))
                .textSelection(.enabled)
                .padding(12)
        }
        .frame(minHeight: 100)
    }

    private func copyCode() {
        Clipboard.copy(code)
    }
}

// MARK: - Non-Scrolling WKWebView

/// Custom WKWebView that passes scroll events to parent for proper scroll passthrough
class NonScrollingWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) {
        // Pass scroll events to the next responder (parent scroll view)
        nextResponder?.scrollWheel(with: event)
    }
}

// MARK: - Mermaid Web View (Local Files)

struct MermaidWebView: NSViewRepresentable {
    let code: String
    let isDark: Bool
    @Binding var height: CGFloat
    @Binding var isLoading: Bool
    @Binding var hasError: Bool
    @Binding var errorMessage: String?

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "mermaidResult")
        contentController.add(context.coordinator, name: "mermaidError")
        config.userContentController = contentController

        let webView = NonScrollingWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")

        context.coordinator.webView = webView
        context.coordinator.loadContent(code: code, isDark: isDark)

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastCode != code || context.coordinator.lastIsDark != isDark {
            context.coordinator.lastCode = code
            context.coordinator.lastIsDark = isDark
            context.coordinator.loadContent(code: code, isDark: isDark)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: MermaidWebView
        weak var webView: WKWebView?
        var lastCode: String = ""
        var lastIsDark: Bool = false
        private var currentHTMLFile: URL?

        init(_ parent: MermaidWebView) {
            self.parent = parent
        }

        deinit {
            if let file = currentHTMLFile {
                try? FileManager.default.removeItem(at: file)
            }
        }

        func loadContent(code: String, isDark: Bool) {
            guard let webView = webView else { return }
            guard let tempDir = MermaidResourceManager.shared.tempDir else {
                DispatchQueue.main.async {
                    self.parent.hasError = true
                    self.parent.errorMessage = "Failed to setup mermaid resources"
                    self.parent.isLoading = false
                }
                return
            }

            let escapedCode = code
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
                .replacingOccurrences(of: "$", with: "\\$")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "")
                .replacingOccurrences(of: "'", with: "\\'")

            let bgColor = isDark ? "#1e1e1e" : "#ffffff"
            let textColor = isDark ? "#e0e0e0" : "#1a1a1a"
            let lineColor = isDark ? "#666666" : "#333333"
            let theme = isDark ? "dark" : "default"

            let html = """
            <!DOCTYPE html>
            <html>
            <head>
                <meta charset="UTF-8">
                <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
                <script src="mermaid.min.js"></script>
                <style>
                    * { margin: 0; padding: 0; box-sizing: border-box; }
                    html, body {
                        background: \(bgColor);
                        overflow: hidden;
                        -webkit-overflow-scrolling: touch;
                    }
                    body { padding: 16px; }
                    #diagram {
                        display: flex;
                        justify-content: center;
                        overflow: visible;
                    }
                    .mermaid {
                        font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                    }
                    #diagram svg {
                        max-width: 100%;
                        height: auto;
                        display: block;
                    }
                    #error {
                        color: #ff6b6b;
                        font-family: -apple-system, monospace;
                        font-size: 12px;
                        padding: 8px;
                        background: rgba(255,0,0,0.1);
                        border-radius: 4px;
                        display: none;
                    }
                </style>
            </head>
            <body>
                <div id="error"></div>
                <div id="diagram" class="mermaid"></div>
                <script>
                    function init() {
                        if (typeof mermaid === 'undefined') {
                            setTimeout(init, 50);
                            return;
                        }

                        mermaid.initialize({
                            startOnLoad: false,
                            theme: '\(theme)',
                            securityLevel: 'strict',
                            themeVariables: {
                                background: '\(bgColor)',
                                primaryTextColor: '\(textColor)',
                                lineColor: '\(lineColor)',
                                textColor: '\(textColor)'
                            }
                        });

                        render();
                    }

                    async function render() {
                        try {
                            const code = `\(escapedCode)`;
                            const { svg } = await mermaid.render('mermaid-svg', code);
                            document.getElementById('diagram').innerHTML = svg;

                            setTimeout(() => {
                                const el = document.getElementById('diagram');
                                const height = el.scrollHeight + 32;
                                window.webkit.messageHandlers.mermaidResult.postMessage({ height: height });
                            }, 100);
                        } catch (e) {
                            const errMsg = e.message || String(e);
                            document.getElementById('error').textContent = errMsg;
                            document.getElementById('error').style.display = 'block';
                            window.webkit.messageHandlers.mermaidError.postMessage(errMsg);
                        }
                    }

                    init();
                </script>
            </body>
            </html>
            """

            // Write HTML to temp file and use loadFileURL
            if let existingFile = currentHTMLFile {
                try? FileManager.default.removeItem(at: existingFile)
                currentHTMLFile = nil
            }
            let htmlFile = tempDir.appendingPathComponent("diagram-\(UUID().uuidString).html")
            do {
                try html.write(to: htmlFile, atomically: true, encoding: .utf8)
                currentHTMLFile = htmlFile
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
                if message.name == "mermaidResult", let body = message.body as? [String: Any] {
                    if let height = body["height"] as? CGFloat {
                        self.parent.height = max(height, 100)
                    }
                    self.parent.isLoading = false
                    self.parent.hasError = false
                    self.parent.errorMessage = nil
                } else if message.name == "mermaidError" {
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
