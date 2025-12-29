//
//  AppDetector.swift
//  aizen
//
//  Detects installed applications and provides their icons
//

import Foundation
import AppKit
import Combine
import os.log

struct DetectedApp: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let bundleIdentifier: String
    let path: URL
    let icon: NSImage?
    let category: AppCategory

    static func == (lhs: DetectedApp, rhs: DetectedApp) -> Bool {
        lhs.bundleIdentifier == rhs.bundleIdentifier
    }
}

enum AppCategory: String {
    case terminal = "Terminal"
    case editor = "Editor"
    case finder = "System"
}

@MainActor
class AppDetector: ObservableObject {
    static let shared = AppDetector()

    @Published var detectedApps: [DetectedApp] = []
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen.app", category: "AppDetector")

    private static let knownApps: [(name: String, bundleId: String, category: AppCategory)] = [
        // Terminals
        ("Terminal", "com.apple.Terminal", .terminal),
        ("iTerm", "com.googlecode.iterm2", .terminal),
        ("Warp", "dev.warp.Warp-Stable", .terminal),
        ("Alacritty", "org.alacritty", .terminal),
        ("Kitty", "net.kovidgoyal.kitty", .terminal),
        ("Hyper", "co.zeit.hyper", .terminal),
        ("Ghostty", "com.mitchellh.ghostty", .terminal),
        ("Rio", "com.raphamorim.rio", .terminal),

        // Editors
        ("Xcode", "com.apple.dt.Xcode", .editor),
        ("Visual Studio Code", "com.microsoft.VSCode", .editor),
        ("VSCodium", "com.visualstudio.code.oss", .editor),
        ("Cursor", "com.todesktop.230313mzl4w4u92", .editor),
        ("Antigravity", "com.google.antigravity", .editor),
        ("Windsurf", "com.codeium.windsurf", .editor),
        ("Sublime Text", "com.sublimetext.4", .editor),
        ("Nova", "com.panic.Nova", .editor),
        ("TextMate", "com.macromates.TextMate", .editor),
        ("Zed", "dev.zed.Zed", .editor),

        // JetBrains IDEs
        ("Android Studio", "com.google.android.studio", .editor),
        ("IntelliJ IDEA", "com.jetbrains.intellij", .editor),
        ("IntelliJ IDEA CE", "com.jetbrains.intellij.ce", .editor),
        ("WebStorm", "com.jetbrains.WebStorm", .editor),
        ("PyCharm", "com.jetbrains.pycharm", .editor),
        ("PyCharm CE", "com.jetbrains.pycharm.ce", .editor),
        ("CLion", "com.jetbrains.CLion", .editor),
        ("GoLand", "com.jetbrains.goland", .editor),
        ("PhpStorm", "com.jetbrains.PhpStorm", .editor),
        ("Rider", "com.jetbrains.rider", .editor),
        ("AppCode", "com.jetbrains.AppCode", .editor),
        ("DataGrip", "com.jetbrains.datagrip", .editor),
        ("RustRover", "com.jetbrains.rustrover", .editor),
        ("Fleet", "com.jetbrains.fleet", .editor),

        // Other editors
        ("Atom", "com.github.atom", .editor),
        ("BBEdit", "com.barebones.bbedit", .editor),
        ("CotEditor", "com.coteditor.CotEditor", .editor),
        ("MacVim", "org.vim.MacVim", .editor),
        ("Emacs", "org.gnu.Emacs", .editor),
        ("Brackets", "io.brackets.appshell", .editor),
        ("TextEdit", "com.apple.TextEdit", .editor),

        // System
        ("Finder", "com.apple.finder", .finder),
    ]

    private init() {
        detectApps()
    }

    func detectApps() {
        var apps: [DetectedApp] = []

        for (name, bundleId, category) in Self.knownApps {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                apps.append(DetectedApp(
                    name: name,
                    bundleIdentifier: bundleId,
                    path: appURL,
                    icon: icon,
                    category: category
                ))
            }
        }

        detectedApps = apps
    }

    func getApps(for category: AppCategory) -> [DetectedApp] {
        detectedApps.filter { $0.category == category }
    }

    func getTerminals() -> [DetectedApp] {
        getApps(for: .terminal)
    }

    func getEditors() -> [DetectedApp] {
        getApps(for: .editor)
    }

    func openPath(_ path: String, with app: DetectedApp) {
        NSWorkspace.shared.open(
            [URL(fileURLWithPath: path)],
            withApplicationAt: app.path,
            configuration: NSWorkspace.OpenConfiguration()
        ) { [self] _, error in
            if let error = error {
                self.logger.error("Failed to open \(app.name): \(error)")
            }
        }
    }
}
