import Foundation

extension MLXModelStore {
    func resolveDownloadItems() async throws -> [DownloadItem] {
        let modelId = normalizedModelId
        let base = "https://huggingface.co/\(modelId)/resolve/main"
        var configPath: String?
        var weightPaths: [String] = []

        if let files = try? await fetchModelFiles() {
            configPath = files.first { $0.hasSuffix("config.json") }

            if let indexPath = files.first(where: { $0.hasSuffix(".safetensors.index.json") }) {
                let indexURL = URL(string: "\(base)/\(indexPath)")!
                let (data, _) = try await session.data(from: indexURL)
                let index = try JSONDecoder().decode(SafetensorsIndex.self, from: data)
                weightPaths = Array(Set(index.weightMap.values)).sorted()
            }

            if weightPaths.isEmpty {
                if let safetensors = files.first(where: { $0.hasSuffix(".safetensors") }) {
                    weightPaths = [safetensors]
                } else if let npz = files.first(where: { $0.hasSuffix(".npz") }) {
                    weightPaths = [npz]
                }
            }
        }

        if configPath == nil {
            configPath = "config.json"
        }

        if weightPaths.isEmpty {
            weightPaths = try await resolveWeightsFallback(base: base)
        }

        guard !weightPaths.isEmpty else {
            throw NSError(domain: "MLXModelStore", code: 404, userInfo: [NSLocalizedDescriptionKey: "No compatible weights found for this model"])
        }

        let configURL = URL(string: "\(base)/\(configPath!)")!
        var items: [DownloadItem] = [
            DownloadItem(url: configURL, destination: modelDirectory.appendingPathComponent("config.json"))
        ]

        for path in weightPaths {
            let url = URL(string: "\(base)/\(path)")!
            items.append(DownloadItem(url: url, destination: modelDirectory.appendingPathComponent((path as NSString).lastPathComponent)))
        }

        return items
    }

    func fetchModelFiles() async throws -> [String] {
        let url = URL(string: "https://huggingface.co/api/models/\(normalizedModelId)")!
        let (data, _) = try await session.data(from: url)
        let info = try JSONDecoder().decode(HFModelInfo.self, from: data)
        return info.siblings.map { $0.rfilename }
    }

    func resolveWeightsFallback(base: String) async throws -> [String] {
        let candidates = ["model.safetensors", "weights.safetensors", "weights.npz", "model.npz"]
        for name in candidates {
            let url = URL(string: "\(base)/\(name)")!
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            do {
                let (_, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) {
                    return [name]
                }
            } catch {
                continue
            }
        }
        return []
    }
}
