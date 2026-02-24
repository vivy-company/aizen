//
//  MarkdownView.swift
//  aizen
//
//  VVDevKit-backed markdown renderer for chat and previews
//

import Foundation
import SwiftUI
import VVMarkdown

struct MarkdownView: View {
    let content: String
    var isStreaming: Bool = false
    var basePath: String? = nil
    var onOpenFileInEditor: ((String) -> Void)? = nil

    @AppStorage(ChatSettings.fontSizeKey) private var chatFontSize = ChatSettings.defaultFontSize
    @Environment(\.colorScheme) private var colorScheme

    private var resolvedBasePath: String? {
        guard let basePath, !basePath.isEmpty else { return nil }
        let expanded = (basePath as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory),
           !isDirectory.boolValue {
            return (expanded as NSString).deletingLastPathComponent
        }
        return expanded
    }

    private var theme: MarkdownTheme {
        var resolvedTheme = colorScheme == .dark ? MarkdownTheme.dark : MarkdownTheme.light
        resolvedTheme.contentPadding = 14
        return resolvedTheme
    }

    private var resolvedBaseURL: URL? {
        guard let resolvedBasePath else { return nil }
        return URL(fileURLWithPath: resolvedBasePath, isDirectory: true)
    }

    var body: some View {
        VVMarkdownView(
            content: content,
            theme: theme,
            font: .systemFont(ofSize: CGFloat(chatFontSize)),
            baseURL: resolvedBaseURL,
            linkHandler: handleLink
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @MainActor
    private func handleLink(_ context: VVMarkdownLinkContext) -> VVMarkdownLinkDecision {
        guard let destination = existingDestinationPath(from: context) else {
            return .openExternally
        }

        if let onOpenFileInEditor {
            onOpenFileInEditor(destination)
        } else {
            NotificationCenter.default.post(
                name: .openFileInEditor,
                object: nil,
                userInfo: ["path": destination]
            )
        }

        return .handled
    }

    private func existingDestinationPath(from context: VVMarkdownLinkContext) -> String? {
        guard let path = destinationPath(from: context) else { return nil }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) ? path : nil
    }

    private func destinationPath(from context: VVMarkdownLinkContext) -> String? {
        if let resolvedURL = context.resolvedURL,
           let path = destinationPath(from: resolvedURL) {
            return path
        }

        if let rawURL = URL(string: context.raw),
           let path = destinationPath(from: rawURL) {
            return path
        }

        let raw = context.raw.removingPercentEncoding ?? context.raw
        guard raw.contains("/") else { return nil }
        return resolveToAbsolutePath(raw)
    }

    private func destinationPath(from url: URL) -> String? {
        if url.scheme?.lowercased() == "aizen-file" {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let rawPath = components.queryItems?.first(where: { $0.name == "path" })?.value,
                  !rawPath.isEmpty else {
                return nil
            }
            return resolveToAbsolutePath(rawPath)
        }

        if url.isFileURL {
            let stripped = stripLineColumnSuffix(url.path)
            return URL(fileURLWithPath: stripped).standardizedFileURL.path
        }

        if url.scheme == nil {
            let raw = url.relativeString.removingPercentEncoding ?? url.relativeString
            guard raw.contains("/") else { return nil }
            return resolveToAbsolutePath(raw)
        }

        return nil
    }

    private func resolveToAbsolutePath(_ rawPath: String) -> String {
        let stripped = stripLineColumnSuffix(rawPath)
        let expanded = (stripped as NSString).expandingTildeInPath

        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded).standardizedFileURL.path
        }

        if let resolvedBasePath, !resolvedBasePath.isEmpty {
            return URL(fileURLWithPath: resolvedBasePath)
                .appendingPathComponent(expanded)
                .standardizedFileURL
                .path
        }

        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(expanded)
            .standardizedFileURL
            .path
    }

    private func stripLineColumnSuffix(_ path: String) -> String {
        let parts = path.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return path }

        if Int(parts[parts.count - 1]) != nil {
            if parts.count >= 3, Int(parts[parts.count - 2]) != nil {
                return parts.dropLast(2).joined(separator: ":")
            }
            return parts.dropLast().joined(separator: ":")
        }

        return path
    }
}
