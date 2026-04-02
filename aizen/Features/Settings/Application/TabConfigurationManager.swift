//
//  TabConfigurationManager.swift
//  aizen
//

import Foundation
import SwiftUI
import Combine
import os.log

extension Notification.Name {
    static let tabConfigurationDidChange = Notification.Name("tabConfigurationDidChange")
}

class TabConfigurationManager: ObservableObject {
    static let shared = TabConfigurationManager()

    private let defaults: UserDefaults
    private let orderKey = "tabOrder"
    private let defaultTabKey = "defaultTab"
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "TabConfigurationManager")

    @Published private(set) var tabOrder: [TabItem] = TabItem.defaultOrder
    @Published private(set) var defaultTab: String = "chat"

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadConfiguration()
    }

    // MARK: - Load/Save

    private func loadConfiguration() {
        loadTabOrder()
        loadDefaultTab()
    }

    private func loadTabOrder() {
        guard let data = defaults.data(forKey: orderKey),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            tabOrder = TabItem.defaultOrder
            return
        }

        // Rebuild order from stored IDs, validating each exists
        var order: [TabItem] = []
        for id in decoded {
            if let tab = TabItem.from(id: id) {
                order.append(tab)
            }
        }

        // Add any missing tabs at the end (future-proofing)
        for defaultTab in TabItem.defaultOrder {
            if !order.contains(defaultTab) {
                order.append(defaultTab)
            }
        }

        tabOrder = order
    }

    private func loadDefaultTab() {
        if let stored = defaults.string(forKey: defaultTabKey),
           TabItem.from(id: stored) != nil {
            defaultTab = stored
        } else {
            defaultTab = "chat"
        }
    }

    private func saveTabOrder() {
        do {
            let ids = tabOrder.map { $0.id }
            let data = try JSONEncoder().encode(ids)
            defaults.set(data, forKey: orderKey)
            NotificationCenter.default.post(name: .tabConfigurationDidChange, object: nil)
        } catch {
            logger.error("Failed to encode tab order: \(error.localizedDescription)")
        }
    }

    private func saveDefaultTab() {
        defaults.set(defaultTab, forKey: defaultTabKey)
        NotificationCenter.default.post(name: .tabConfigurationDidChange, object: nil)
    }

    // MARK: - Public API

    func moveTab(from source: IndexSet, to destination: Int) {
        tabOrder.move(fromOffsets: source, toOffset: destination)
        saveTabOrder()
    }

    func setDefaultTab(_ tabId: String) {
        guard TabItem.from(id: tabId) != nil else { return }
        defaultTab = tabId
        saveDefaultTab()
    }

    func resetToDefaults() {
        tabOrder = TabItem.defaultOrder
        defaultTab = "chat"
        saveTabOrder()
        saveDefaultTab()
    }

    /// Returns the first visible tab from the configured order
    func firstVisibleTab(showChat: Bool, showTerminal: Bool, showFiles: Bool, showBrowser: Bool) -> String {
        for tab in tabOrder {
            switch tab.id {
            case "chat" where showChat: return "chat"
            case "terminal" where showTerminal: return "terminal"
            case "files" where showFiles: return "files"
            case "browser" where showBrowser: return "browser"
            default: continue
            }
        }
        return "files" // Fallback
    }

    /// Returns the effective default tab, accounting for visibility
    func effectiveDefaultTab(showChat: Bool, showTerminal: Bool, showFiles: Bool, showBrowser: Bool) -> String {
        let isVisible: Bool
        switch defaultTab {
        case "chat": isVisible = showChat
        case "terminal": isVisible = showTerminal
        case "files": isVisible = showFiles
        case "browser": isVisible = showBrowser
        default: isVisible = false
        }

        if isVisible {
            return defaultTab
        }

        // Default tab is hidden, fall back to first visible
        return firstVisibleTab(showChat: showChat, showTerminal: showTerminal, showFiles: showFiles, showBrowser: showBrowser)
    }
}
