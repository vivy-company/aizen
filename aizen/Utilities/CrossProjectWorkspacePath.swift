import Foundation

struct WorkspacePathCandidate {
    let id: UUID
    let name: String?
}

enum CrossProjectWorkspacePath {
    private static let fallbackSlug = "workspace"

    static func slugifyWorkspaceName(_ name: String?) -> String {
        let raw = (name ?? "")
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let normalized = String(raw.map { character in
            (character.isLetter || character.isNumber) ? character : "-"
        })

        let collapsed = normalized.replacingOccurrences(
            of: "-+",
            with: "-",
            options: .regularExpression
        )

        let slug = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return slug.isEmpty ? fallbackSlug : slug
    }

    static func folderName(
        for workspaceID: UUID,
        workspaceName: String?,
        allWorkspaces: [WorkspacePathCandidate]
    ) -> String {
        let baseSlug = slugifyWorkspaceName(workspaceName)

        let collisionIDs = allWorkspaces
            .filter { slugifyWorkspaceName($0.name) == baseSlug }
            .map(\.id)
            .sorted { $0.uuidString.localizedCaseInsensitiveCompare($1.uuidString) == .orderedAscending }

        guard let index = collisionIDs.firstIndex(of: workspaceID) else {
            return baseSlug
        }

        return index == 0 ? baseSlug : "\(baseSlug)-\(index)"
    }

    static func rootURL(
        for workspaceID: UUID,
        workspaceName: String?,
        allWorkspaces: [WorkspacePathCandidate],
        fileManager: FileManager = .default
    ) -> URL {
        let folder = folderName(
            for: workspaceID,
            workspaceName: workspaceName,
            allWorkspaces: allWorkspaces
        )

        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("aizen/workspaces", isDirectory: true)
            .appendingPathComponent(folder, isDirectory: true)
    }
}
