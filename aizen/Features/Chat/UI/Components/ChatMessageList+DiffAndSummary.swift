import ACP
import AppKit
import Foundation
import SwiftUI
import VVChatTimeline
import VVCode
import VVMetalPrimitives

extension ChatMessageList {
    func planRequestMarkdown(_ request: RequestPermissionRequest) -> String {
        var sections: [String] = ["**Plan approval requested**"]

        if let message = request.message,
           !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append(message)
        }

        if let toolCall = request.toolCall,
           let rawInput = toolCall.rawInput?.value as? [String: Any],
           let plan = rawInput["plan"] as? String,
           !plan.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append(plan)
        }

        if let options = request.options, !options.isEmpty {
            let optionLines = options.map { "- \($0.name)" }
            sections.append(optionLines.joined(separator: "\n"))
        }

        return sections.joined(separator: "\n\n")
    }

    func resolveSummaryFilePath(_ rawPath: String) -> String {
        let expanded = (rawPath as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded).standardizedFileURL.path
        }

        if let worktreePath, !worktreePath.isEmpty {
            return URL(fileURLWithPath: worktreePath)
                .appendingPathComponent(expanded)
                .standardizedFileURL
                .path
        }

        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(expanded)
            .standardizedFileURL
            .path
    }

    func fileOpenURLString(path: String) -> String {
        var components = URLComponents()
        components.scheme = "aizen-file"
        components.queryItems = [URLQueryItem(name: "path", value: path)]
        return components.url?.absoluteString ?? path
    }

    func decodeCustomPayload(from data: Data) -> TimelineCustomPayload? {
        try? JSONDecoder().decode(TimelineCustomPayload.self, from: data)
    }

    func toolGroupStatusColor(statusRawValue: String?) -> SIMD4<Float> {
        switch statusRawValue {
        case "failed":
            return colorScheme == .dark ? .rgba(0.92, 0.42, 0.44, 1) : .rgba(0.82, 0.24, 0.28, 1)
        case "in_progress":
            return colorScheme == .dark ? .rgba(0.98, 0.78, 0.36, 1) : .rgba(0.88, 0.62, 0.06, 1)
        default:
            return colorScheme == .dark ? .rgba(0.42, 0.82, 0.52, 1) : .rgba(0.14, 0.64, 0.24, 1)
        }
    }

    func toolGroupStatusNSColor(statusRawValue: String?) -> NSColor {
        switch statusRawValue {
        case "failed":
            return colorScheme == .dark
                ? NSColor(red: 0.92, green: 0.42, blue: 0.44, alpha: 1)
                : NSColor(red: 0.82, green: 0.24, blue: 0.28, alpha: 1)
        case "in_progress":
            return colorScheme == .dark
                ? NSColor(red: 0.98, green: 0.78, blue: 0.36, alpha: 1)
                : NSColor(red: 0.88, green: 0.62, blue: 0.06, alpha: 1)
        default:
            return headerIconTintColor
        }
    }
}
