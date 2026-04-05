import Foundation

extension AgentUsageStore {
    func load() {
        guard let data = defaults.data(forKey: storeKey) else { return }
        do {
            statsByAgent = try decoder.decode([String: AgentUsageStats].self, from: data)
        } catch {
            statsByAgent = [:]
        }
    }

    func persist() {
        do {
            let data = try encoder.encode(statsByAgent)
            defaults.set(data, forKey: storeKey)
        } catch {
            // Best effort persistence; ignore write failures.
        }
    }

    func schedulePersist() {
        persistTask?.cancel()
        persistTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(persistDelay))
            persist()
        }
    }
}
