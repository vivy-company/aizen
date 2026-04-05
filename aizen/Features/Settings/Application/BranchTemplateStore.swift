//
//  BranchTemplateStore.swift
//  aizen
//

import Foundation
import SwiftUI
import Combine
import os.log

extension Notification.Name {
    static let branchTemplatesDidChange = Notification.Name("branchTemplatesDidChange")
}

class BranchTemplateStore: ObservableObject {
    static let shared = BranchTemplateStore()

    let defaults: UserDefaults
    let templatesKey = "branchTemplates"
    let legacyKey = "branchNameTemplates"
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "BranchTemplateStore")

    @Published var templates: [BranchTemplate] = []

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        migrateFromLegacyIfNeeded()
        loadTemplates()
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
