import AppKit
import SwiftUI
import os.log

struct RepositoryRow: View {
    private let logger = Logger.workspace
    @ObservedObject var repository: Repository
    let isSelected: Bool
    @ObservedObject var repositoryManager: WorkspaceRepositoryStore
    let onSelect: () -> Void
    let onRemove: () -> Void
    @Environment(\.controlActiveState) var controlActiveState

    @State var showingRemoveConfirmation = false
    @State var alsoDeleteFromFilesystem = false
    @State var showingNoteEditor = false
    @State var showingPostCreateActions = false

    @AppStorage("defaultTerminalBundleId") var defaultTerminalBundleId: String?
    @AppStorage("defaultEditorBundleId") var defaultEditorBundleId: String?

    var defaultTerminal: DetectedApp? {
        guard let bundleId = defaultTerminalBundleId else { return nil }
        return AppDetector.shared.getTerminals().first { $0.bundleIdentifier == bundleId }
    }

    var defaultEditor: DetectedApp? {
        guard let bundleId = defaultEditorBundleId else { return nil }
        return AppDetector.shared.getEditors().first { $0.bundleIdentifier == bundleId }
    }

    var finderApp: DetectedApp? {
        AppDetector.shared.getApps(for: .finder).first
    }

    func sortedApps(_ apps: [DetectedApp], defaultBundleId: String?) -> [DetectedApp] {
        guard let defaultId = defaultBundleId else { return apps }
        var sorted = apps.filter { $0.bundleIdentifier != defaultId }
        if let defaultApp = apps.first(where: { $0.bundleIdentifier == defaultId }) {
            sorted.insert(defaultApp, at: 0)
        }
        return sorted
    }

    var body: some View {
        repositoryLabel
            .background(selectionBackground)
            .contextMenu { repositoryContextMenu }
            .repositoryRowPresentation(view: self)
    }

    func setStatus(_ status: ItemStatus) {
        do {
            try repositoryManager.updateRepositoryStatus(repository, status: status)
        } catch {
            logger.error("Failed to update repository status: \(error.localizedDescription)")
        }
    }

    var repositoryStatus: ItemStatus {
        ItemStatus(rawValue: repository.status ?? "active") ?? .active
    }

    func removeRepository() {
        Task {
            do {
                if alsoDeleteFromFilesystem, let path = repository.path {
                    let fileURL = URL(fileURLWithPath: path)
                    try FileManager.default.removeItem(at: fileURL)
                }

                onRemove()
                try repositoryManager.deleteRepository(repository)
                alsoDeleteFromFilesystem = false
            } catch {
                logger.error("Failed to remove repository: \(error.localizedDescription)")
                alsoDeleteFromFilesystem = false
            }
        }
    }
}
