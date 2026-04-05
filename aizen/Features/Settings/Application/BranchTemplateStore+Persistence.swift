import Foundation
import os.log

extension BranchTemplateStore {
    func migrateFromLegacyIfNeeded() {
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

    func loadTemplates() {
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

    func saveTemplates() {
        do {
            let data = try JSONEncoder().encode(templates)
            defaults.set(data, forKey: templatesKey)
            NotificationCenter.default.post(name: .branchTemplatesDidChange, object: nil)
        } catch {
            logger.error("Failed to encode branch templates: \(error.localizedDescription)")
        }
    }
}
