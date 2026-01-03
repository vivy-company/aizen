import Foundation
import CoreData

final class CLIStore {
    let container: NSPersistentContainer

    init() throws {
        guard let appBundleURL = CLIStore.findAizenAppBundle() else {
            throw CLIError.appNotFound
        }
        let appBundle = Bundle(url: appBundleURL)
        guard let modelURL = appBundle?.url(forResource: "aizen", withExtension: "momd") else {
            throw CLIError.modelNotFound
        }
        guard let model = NSManagedObjectModel(contentsOf: modelURL) else {
            throw CLIError.modelNotFound
        }

        let container = NSPersistentContainer(name: "aizen", managedObjectModel: model)
        let bundleIdentifier = appBundle?.bundleIdentifier ?? "win.aizen.app"
        let storeURL = CLIStore.defaultStoreURL(bundleIdentifier: bundleIdentifier)
        if ProcessInfo.processInfo.environment["AIZEN_CLI_DEBUG"] == "1" {
            fputs("Aizen CLI: using store at \(storeURL.path)\n", stderr)
        }
        try? FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let description = NSPersistentStoreDescription(url: storeURL)
        description.type = NSSQLiteStoreType
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        container.loadPersistentStores { _, error in
            loadError = error
            semaphore.signal()
        }
        semaphore.wait()
        if let error = loadError {
            throw CLIError.storeLoadFailed(error.localizedDescription)
        }
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
        self.container = container
    }

    static func findAizenAppBundle() -> URL? {
        let candidates = [
            "/Applications/Aizen.app",
            "/Applications/Aizen Nightly.app",
            (FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Aizen.app")).path,
            (FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Aizen Nightly.app")).path
        ]

        for path in candidates {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    private static func defaultStoreURL(bundleIdentifier: String) -> URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let defaultDirectory = appSupport.appendingPathComponent(bundleIdentifier, isDirectory: true)
        let defaultURL = defaultDirectory.appendingPathComponent("aizen.sqlite")

        if let override = storeOverrideURL() {
            return override
        }

        let legacyURL = appSupport.appendingPathComponent("aizen", isDirectory: true)
            .appendingPathComponent("aizen.sqlite")

        let candidates = [
            legacyURL,
            containerStoreURL(bundleIdentifier: bundleIdentifier),
            containerStoreURL(bundleIdentifier: "win.aizen.app"),
            containerStoreURL(bundleIdentifier: "win.aizen.app.nightly"),
            appSupport.appendingPathComponent("win.aizen.app", isDirectory: true).appendingPathComponent("aizen.sqlite"),
            appSupport.appendingPathComponent("win.aizen.app.nightly", isDirectory: true).appendingPathComponent("aizen.sqlite"),
            defaultURL
        ]

        if let best = pickMostRecentStore(from: candidates) {
            return best
        }

        return defaultURL
    }

    private static func storeOverrideURL() -> URL? {
        let env = ProcessInfo.processInfo.environment
        guard let raw = env["AIZEN_STORE_PATH"], !raw.isEmpty else {
            return nil
        }
        let expanded = (raw as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded).standardizedFileURL
    }

    private static func containerStoreURL(bundleIdentifier: String) -> URL {
        let fileManager = FileManager.default
        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers")
            .appendingPathComponent(bundleIdentifier)
            .appendingPathComponent("Data/Library/Application Support", isDirectory: true)
            .appendingPathComponent("aizen.sqlite")
    }

    private static func pickMostRecentStore(from urls: [URL]) -> URL? {
        let fileManager = FileManager.default
        var bestURL: URL?
        var bestDate = Date.distantPast
        var bestSize: Int64 = -1

        for url in urls {
            guard fileManager.fileExists(atPath: url.path) else { continue }
            let attrs = try? fileManager.attributesOfItem(atPath: url.path)
            let date = (attrs?[.modificationDate] as? Date) ?? Date.distantPast
            let size = (attrs?[.size] as? Int64) ?? 0
            if date > bestDate || (date == bestDate && size > bestSize) {
                bestDate = date
                bestSize = size
                bestURL = url
            }
        }

        return bestURL
    }
}
