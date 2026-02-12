import Foundation
import CoreData

final class CLIRepositoryManager {
    static let crossProjectRepositoryMarker = "__aizen.cross_project.workspace_repo__"

    private let context: NSManagedObjectContext
    private let statusService = GitStatusService()
    private let branchService = GitBranchService()
    private let worktreeService = GitWorktreeService()
    private let remoteService = GitRemoteService()
    private let postCreateExecutor = PostCreateActionExecutor()

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    private func isCrossProjectRepository(_ repository: Repository) -> Bool {
        repository.isCrossProject || repository.note == Self.crossProjectRepositoryMarker
    }

    private func visibleRepositories(in workspace: Workspace) -> [Repository] {
        let repositories = (workspace.repositories as? Set<Repository>) ?? []
        return repositories
            .filter { !isCrossProjectRepository($0) }
            .sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    private func crossProjectRootURL(for workspace: Workspace) throws -> URL {
        guard let workspaceId = workspace.id else {
            throw CLIError.invalidArguments("Workspace identifier is missing")
        }

        let workspaceRequest: NSFetchRequest<Workspace> = Workspace.fetchRequest()
        let allWorkspaces = try context.fetch(workspaceRequest)
        let candidates = allWorkspaces.compactMap { candidate -> WorkspacePathCandidate? in
            guard let candidateID = candidate.id else {
                return nil
            }
            return WorkspacePathCandidate(id: candidateID, name: candidate.name)
        }

        return CrossProjectWorkspacePath.rootURL(
            for: workspaceId,
            workspaceName: workspace.name,
            allWorkspaces: candidates
        )
    }

    private func prepareCrossProjectDirectory(for workspace: Workspace) throws -> URL {
        let fileManager = FileManager.default
        let rootURL = try crossProjectRootURL(for: workspace)

        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let existingItems = try fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)
        for itemURL in existingItems {
            try? fileManager.removeItem(at: itemURL)
        }

        var usedNames = Set<String>()
        for repository in visibleRepositories(in: workspace) {
            guard let sourcePath = repository.path, fileManager.fileExists(atPath: sourcePath) else {
                continue
            }

            let fallbackName = URL(fileURLWithPath: sourcePath).lastPathComponent
            let rawName = (repository.name?.isEmpty == false ? repository.name! : fallbackName)
            let sanitizedName = rawName
                .replacingOccurrences(of: "/", with: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let baseName = sanitizedName.isEmpty ? "project" : sanitizedName

            var linkName = baseName
            var suffix = 2
            while usedNames.contains(linkName) {
                linkName = "\(baseName)-\(suffix)"
                suffix += 1
            }
            usedNames.insert(linkName)

            let linkURL = rootURL.appendingPathComponent(linkName)
            if fileManager.fileExists(atPath: linkURL.path) {
                try? fileManager.removeItem(at: linkURL)
            }

            try fileManager.createSymbolicLink(atPath: linkURL.path, withDestinationPath: sourcePath)
        }

        return rootURL
    }

    func ensureCrossProjectWorktree(for workspace: Workspace) throws -> Worktree {
        let rootURL = try prepareCrossProjectDirectory(for: workspace)

        let repositoryRequest: NSFetchRequest<Repository> = Repository.fetchRequest()
        repositoryRequest.fetchLimit = 1
        repositoryRequest.predicate = NSPredicate(
            format: "workspace == %@ AND (isCrossProject == YES OR note == %@)",
            workspace,
            Self.crossProjectRepositoryMarker
        )

        let repository = try context.fetch(repositoryRequest).first ?? Repository(context: context)
        if repository.id == nil {
            repository.id = UUID()
        }
        repository.name = "Cross-Project"
        repository.path = rootURL.path
        repository.note = Self.crossProjectRepositoryMarker
        repository.isCrossProject = true
        repository.status = "active"
        repository.workspace = workspace
        repository.lastUpdated = Date()

        let existingWorktrees = (repository.worktrees as? Set<Worktree>) ?? []
        let worktree = existingWorktrees.first(where: { $0.isPrimary }) ?? existingWorktrees.first ?? Worktree(context: context)
        if worktree.id == nil {
            worktree.id = UUID()
        }
        worktree.path = rootURL.path
        worktree.branch = "workspace"
        worktree.isPrimary = true
        worktree.repository = repository
        worktree.lastAccessed = Date()

        if context.hasChanges {
            try context.save()
        }

        return worktree
    }

    func createWorkspace(name: String, colorHex: String? = nil) throws -> Workspace {
        let workspace = Workspace(context: context)
        workspace.id = UUID()
        workspace.name = name
        workspace.colorHex = colorHex

        let fetchRequest: NSFetchRequest<Workspace> = Workspace.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Workspace.order, ascending: false)]
        fetchRequest.fetchLimit = 1

        if let lastWorkspace = try? context.fetch(fetchRequest).first {
            workspace.order = lastWorkspace.order + 1
        } else {
            workspace.order = 0
        }

        try context.save()
        return workspace
    }

    func updateWorkspace(_ workspace: Workspace, name: String? = nil, colorHex: String? = nil) throws {
        if let name = name {
            workspace.name = name
        }
        if let colorHex = colorHex {
            workspace.colorHex = colorHex
        }
        try context.save()
    }

    func deleteWorkspace(_ workspace: Workspace) throws {
        context.delete(workspace)
        try context.save()
    }

    func addExistingRepository(path: String, workspace: Workspace) async throws -> Repository {
        guard await GitUtils.isGitRepository(at: path) else {
            throw CLIError.notGitRepository(path)
        }

        let mainRepoPath = await GitUtils.getMainRepositoryPath(at: path)

        let fetchRequest: NSFetchRequest<Repository> = Repository.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "path == %@", mainRepoPath)

        if let existing = try? context.fetch(fetchRequest).first {
            existing.workspace = workspace
            try context.save()
            return existing
        }

        let repository = Repository(context: context)
        repository.id = UUID()
        repository.path = mainRepoPath
        repository.name = try await remoteService.getRepositoryName(at: mainRepoPath)
        repository.workspace = workspace
        repository.lastUpdated = Date()

        try await scanWorktrees(for: repository)

        try context.save()
        return repository
    }

    func cloneRepository(url: String, destinationPath: String, workspace: Workspace) async throws -> Repository {
        let repoName = extractRepoName(from: url)
        let fullPath = (destinationPath as NSString).appendingPathComponent(repoName)
        try await remoteService.clone(url: url, to: fullPath)
        return try await addExistingRepository(path: fullPath, workspace: workspace)
    }

    func createNewRepository(path: String, name: String, workspace: Workspace) async throws -> Repository {
        let fullPath = (path as NSString).appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: fullPath) {
            throw CLIError.ioError("Directory already exists: \(fullPath)")
        }
        try await remoteService.initRepository(at: fullPath)
        return try await addExistingRepository(path: fullPath, workspace: workspace)
    }

    func deleteRepository(_ repository: Repository) throws {
        context.delete(repository)
        try context.save()
    }

    func updateRepositoryNote(_ repository: Repository, note: String?) throws {
        repository.note = note
        try context.save()
    }

    func updateWorktreeNote(_ worktree: Worktree, note: String?) throws {
        worktree.note = note
        try context.save()
    }

    func refreshRepository(_ repository: Repository) async throws {
        guard let repositoryPath = repository.path else {
            throw CLIError.invalidArguments("Repository path is nil")
        }
        guard FileManager.default.fileExists(atPath: repositoryPath) else {
            throw CLIError.repositoryNotFound(repositoryPath)
        }
        repository.lastUpdated = Date()
        try await scanWorktrees(for: repository)
        if context.hasChanges {
            try context.save()
        }
    }

    func scanWorktrees(for repository: Repository) async throws {
        guard let repositoryPath = repository.path else {
            throw CLIError.invalidArguments("Repository path is nil")
        }

        let worktreeInfos = try await worktreeService.listWorktrees(at: repositoryPath)
        let validPaths = Set(worktreeInfos.map { $0.path })
        let existingWorktrees = (repository.worktrees as? Set<Worktree>) ?? []

        var seenPaths = Set<String>()
        for wt in existingWorktrees {
            guard var path = wt.path else {
                context.delete(wt)
                continue
            }

            if !path.hasPrefix("/") {
                path = "/" + path
                wt.path = path
            }

            if !validPaths.contains(path) || seenPaths.contains(path) {
                context.delete(wt)
            } else {
                seenPaths.insert(path)
            }
        }

        let remainingWorktrees = (repository.worktrees as? Set<Worktree>) ?? []
        var worktreesByPath: [String: Worktree] = [:]
        for wt in remainingWorktrees {
            if let path = wt.path {
                worktreesByPath[path] = wt
            }
        }

        for info in worktreeInfos {
            if let existing = worktreesByPath[info.path] {
                existing.branch = info.branch
                existing.isPrimary = info.isPrimary
            } else {
                let worktree = Worktree(context: context)
                worktree.id = UUID()
                worktree.path = info.path
                worktree.branch = info.branch
                worktree.isPrimary = info.isPrimary
                worktree.repository = repository
            }
        }
    }

    func addWorktree(
        to repository: Repository,
        path: String,
        branch: String,
        createBranch: Bool,
        baseBranch: String? = nil
    ) async throws -> Worktree {
        guard let repoPath = repository.path else {
            throw CLIError.invalidArguments("Repository path is nil")
        }

        let repoName = URL(fileURLWithPath: repoPath).lastPathComponent
        let worktreesDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("aizen/worktrees")
            .appendingPathComponent(repoName)
        try? FileManager.default.createDirectory(at: worktreesDir, withIntermediateDirectories: true)

        try await worktreeService.addWorktree(at: repoPath, path: path, branch: branch, createBranch: createBranch, baseBranch: baseBranch)

        let worktree = Worktree(context: context)
        worktree.id = UUID()
        worktree.path = path
        worktree.branch = branch
        worktree.isPrimary = false
        worktree.repository = repository
        worktree.lastAccessed = Date()

        try context.save()

        await executePostCreateActions(for: repository, newWorktreePath: path)

        return worktree
    }

    private func executePostCreateActions(for repository: Repository, newWorktreePath: String) async {
        let actions = repository.postCreateActions
        guard !actions.isEmpty else { return }

        guard let mainWorktreePath = findMainWorktreePath(for: repository) else {
            return
        }

        _ = await postCreateExecutor.execute(
            actions: actions,
            newWorktreePath: newWorktreePath,
            mainWorktreePath: mainWorktreePath
        )
    }

    private func findMainWorktreePath(for repository: Repository) -> String? {
        if let worktrees = repository.worktrees as? Set<Worktree>,
           let primary = worktrees.first(where: { $0.isPrimary }) {
            return primary.path
        }
        return repository.path
    }

    func deleteWorktree(_ worktree: Worktree, force: Bool = false) async throws {
        guard let repository = worktree.repository,
              let repoPath = repository.path,
              let worktreePath = worktree.path else {
            throw CLIError.invalidArguments("Worktree path is nil")
        }

        try await worktreeService.removeWorktree(at: worktreePath, repoPath: repoPath, force: force)
        context.delete(worktree)
        try context.save()
    }

    private func extractRepoName(from url: String) -> String {
        var name = URL(string: url)?.lastPathComponent ?? url
        if name.hasSuffix(".git") {
            name = String(name.dropLast(4))
        }
        if name.isEmpty || name == "/" {
            name = "repository"
        }
        return name
    }
}
