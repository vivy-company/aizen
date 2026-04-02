//
//  BranchTemplateManager.swift
//  aizen
//

import Foundation
import SwiftUI
import Combine
import os.log

extension Notification.Name {
    static let branchTemplatesDidChange = Notification.Name("branchTemplatesDidChange")
}

class BranchTemplateManager: ObservableObject {
    static let shared = BranchTemplateManager()

    private let defaults: UserDefaults
    private let templatesKey = "branchTemplates"
    private let legacyKey = "branchNameTemplates"
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "BranchTemplateManager")

    @Published private(set) var templates: [BranchTemplate] = []

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        migrateFromLegacyIfNeeded()
        loadTemplates()
    }

    private func migrateFromLegacyIfNeeded() {
        guard defaults.data(forKey: templatesKey) == nil,
              let legacyData = defaults.data(forKey: legacyKey),
              let legacyTemplates = try? JSONDecoder().decode([String].self, from: legacyData) else {
            return
        }

        let newTemplates = legacyTemplates.map { prefix in
            BranchTemplate(prefix: prefix)
        }

        do {
            let data = try JSONEncoder().encode(newTemplates)
            defaults.set(data, forKey: templatesKey)
            defaults.removeObject(forKey: legacyKey)
            logger.info("Migrated \(legacyTemplates.count) branch templates from legacy format")
        } catch {
            logger.error("Failed to migrate branch templates: \(error.localizedDescription)")
        }
    }

    private func loadTemplates() {
        guard let data = defaults.data(forKey: templatesKey) else {
            templates = []
            return
        }

        do {
            templates = try JSONDecoder().decode([BranchTemplate].self, from: data)
        } catch {
            logger.error("Failed to decode branch templates: \(error.localizedDescription)")
            templates = []
        }
    }

    private func saveTemplates() {
        do {
            let data = try JSONEncoder().encode(templates)
            defaults.set(data, forKey: templatesKey)
            NotificationCenter.default.post(name: .branchTemplatesDidChange, object: nil)
        } catch {
            logger.error("Failed to encode branch templates: \(error.localizedDescription)")
        }
    }

    func addTemplate(prefix: String, icon: String = "arrow.triangle.branch") {
        let template = BranchTemplate(prefix: prefix, icon: icon)
        templates.append(template)
        saveTemplates()
    }

    func updateTemplate(_ template: BranchTemplate) {
        guard let index = templates.firstIndex(where: { $0.id == template.id }) else { return }
        templates[index] = template
        saveTemplates()
    }

    func deleteTemplate(id: UUID) {
        templates.removeAll { $0.id == id }
        saveTemplates()
    }

    func moveTemplate(from source: IndexSet, to destination: Int) {
        templates.move(fromOffsets: source, toOffset: destination)
        saveTemplates()
    }

    var prefixes: [String] {
        templates.map(\.prefix)
    }
}
