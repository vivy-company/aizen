//
//  PostCreateTemplateStore.swift
//  aizen
//

import Foundation
import Combine
import os.log

@MainActor
class PostCreateTemplateStore: ObservableObject {
    static let shared = PostCreateTemplateStore()

    @Published var customTemplates: [PostCreateTemplate] = []

    private let userDefaultsKey = "postCreateTemplates"
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen.app", category: "PostCreateTemplateStore")

    init() {
        loadTemplates()
    }

    /// All available templates (built-in + custom)
    var allTemplates: [PostCreateTemplate] {
        PostCreateTemplate.builtInTemplates + customTemplates
    }

    func saveTemplate(_ template: PostCreateTemplate) {
        if let index = customTemplates.firstIndex(where: { $0.id == template.id }) {
            customTemplates[index] = template
        } else {
            customTemplates.append(template)
        }
        saveTemplates()
    }

    func deleteTemplate(id: UUID) {
        customTemplates.removeAll { $0.id == id }
        saveTemplates()
    }

    func isBuiltIn(_ template: PostCreateTemplate) -> Bool {
        PostCreateTemplate.builtInTemplates.contains { $0.id == template.id }
    }

    private func loadTemplates() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else { return }
        do {
            customTemplates = try JSONDecoder().decode([PostCreateTemplate].self, from: data)
        } catch {
            logger.error("Failed to load custom templates: \(error.localizedDescription)")
        }
    }

    private func saveTemplates() {
        do {
            let data = try JSONEncoder().encode(customTemplates)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } catch {
            logger.error("Failed to save custom templates: \(error.localizedDescription)")
        }
    }
}
