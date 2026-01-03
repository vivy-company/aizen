import Foundation
import CoreData
import Darwin

@MainActor
@main
struct AizenCLI {
    static func main() async {
        do {
            try await run()
            exit(ExitCode.success.rawValue)
        } catch let error as CLIError {
            printError(error.localizedDescription)
            exit(error.exitCode.rawValue)
        } catch {
            printError(error.localizedDescription)
            exit(ExitCode.generalError.rawValue)
        }
    }

    static func run() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.isEmpty {
            try openApp()
            return
        }

        let command = args[0]
        let subArgs = Array(args.dropFirst())

        switch command {
        case "-h", "--help", "help":
            print(helpText())
        case "open":
            try await handleOpen(subArgs)
        case "add":
            try await handleAdd(subArgs)
        case "remove":
            try await handleRemove(subArgs)
        case "list", "ls":
            try await handleList(subArgs)
        case "workspace", "ws":
            try await handleWorkspace(subArgs)
        case "sync":
            try await handleSync(subArgs)
        case "status":
            try await handleStatus(subArgs)
        default:
            throw CLIError.invalidArguments("Unknown command: \(command)")
        }
    }
}

private extension AizenCLI {
    static func handleOpen(_ args: [String]) async throws {
        if args.contains("--help") || args.contains("-h") {
            print(openHelpText())
            return
        }
        if args.isEmpty {
            try openApp()
            return
        }
        if args.count > 1 {
            throw CLIError.invalidArguments("Too many arguments for open")
        }
        let path = normalizePath(args[0])
        try openApp(path: path)
    }

    static func handleAdd(_ args: [String]) async throws {
        let parsed = try parseArguments(args)
        if parsed.flags.contains("help") {
            print(addHelpText())
            return
        }
        guard parsed.positionals.count <= 1 else {
            throw CLIError.invalidArguments("Too many arguments for add")
        }

        let store = try CLIStore()
        let manager = CLIRepositoryManager(context: store.container.viewContext)
        let style = OutputStyle(useColor: shouldUseColor(flags: parsed.flags))

        let target = parsed.positionals.first
        let workspace = try selectWorkspace(
            in: store.container.viewContext,
            preferredName: parsed.options["workspace"],
            defaultWorkspaceId: readDefaultSetting(key: "defaultWorkspaceId")
        )

        if let target = target {
            if isRemoteURL(target) {
                let destination = parsed.options["destination"] ?? defaultCloneDestination()
                let destinationPath = normalizePath(destination)
                try ensureDirectoryExists(destinationPath)
                let repository = try await manager.cloneRepository(
                    url: target,
                    destinationPath: destinationPath,
                    workspace: workspace
                )
                if let repoPath = repository.path {
                    try ensureAizenGitignore(at: repoPath)
                }
                print(style.success("Added repository: \(repository.name ?? "")"))
                return
            }

            let path = normalizePath(target)
            let repository = try await manager.addExistingRepository(path: path, workspace: workspace)
            print(style.success("Added repository: \(repository.name ?? "")"))
            return
        }

        let cwd = FileManager.default.currentDirectoryPath
        let repository = try await manager.addExistingRepository(path: cwd, workspace: workspace)
        print(style.success("Added repository: \(repository.name ?? "")"))
    }

    static func handleRemove(_ args: [String]) async throws {
        let parsed = try parseArguments(args)
        if parsed.flags.contains("help") {
            print(removeHelpText())
            return
        }
        guard parsed.positionals.count == 1 else {
            throw CLIError.invalidArguments("remove requires a path argument")
        }

        let store = try CLIStore()
        let context = store.container.viewContext
        let manager = CLIRepositoryManager(context: context)
        let style = OutputStyle(useColor: shouldUseColor(flags: parsed.flags))

        let path = normalizePath(parsed.positionals[0])
        guard let repository = findRepository(for: path, in: context) else {
            throw CLIError.repositoryNotFound(path)
        }

        try manager.deleteRepository(repository)
        print(style.success("Removed repository: \(repository.name ?? "")"))
    }

    static func handleList(_ args: [String]) async throws {
        let parsed = try parseArguments(args)
        if parsed.flags.contains("help") {
            print(listHelpText())
            return
        }
        guard parsed.positionals.count <= 1 else {
            throw CLIError.invalidArguments("Too many arguments for list")
        }

        let store = try CLIStore()
        let context = store.container.viewContext

        let workspaceFilter = parsed.positionals.first
        let filters = repositoryFilters(from: parsed, positionalWorkspace: workspaceFilter)
        let repositories = try fetchRepositories(in: context, filters: filters)
        let style = OutputStyle(useColor: shouldUseColor(flags: parsed.flags))

        if parsed.flags.contains("json") {
            let payload = RepositoryListPayload(
                filters: filters,
                repositories: repositories.map(repositoryOutput)
            )
            printJSON(payload)
            return
        }

        if repositories.isEmpty {
            if !filters.includeWorkspaces.isEmpty {
                let names = filters.includeWorkspaces.sorted().joined(separator: ", ")
                print("No repositories found in workspace(s): \(names)")
            } else {
                print("No repositories found")
            }
            return
        }

        let title = filters.includeWorkspaces.isEmpty
            ? "Repositories (\(repositories.count))"
            : "Repositories (\(repositories.count)) in \(filters.includeWorkspaces.joined(separator: ", "))"
        printSectionTitle(title, style: style)
        printRepositoryTable(repositories, style: style)
    }

    static func handleWorkspace(_ args: [String]) async throws {
        if args.contains("--help") || args.contains("-h") {
            print(workspaceHelpText())
            return
        }
        if args.isEmpty {
            try await handleWorkspaceList([])
            return
        }

        let subcommand = args[0]
        let rest = Array(args.dropFirst())

        switch subcommand {
        case "list":
            try await handleWorkspaceList(rest)
        case "new":
            try await handleWorkspaceNew(rest)
        case "delete":
            try await handleWorkspaceDelete(rest)
        case "rename":
            try await handleWorkspaceRename(rest)
        default:
            throw CLIError.invalidArguments("Unknown workspace command: \(subcommand)")
        }
    }

    static func handleWorkspaceList(_ args: [String]) async throws {
        let parsed = try parseArguments(args)
        if parsed.flags.contains("help") {
            print(workspaceListHelpText())
            return
        }
        guard parsed.positionals.isEmpty else {
            throw CLIError.invalidArguments("workspace list does not take arguments")
        }

        let store = try CLIStore()
        let context = store.container.viewContext

        let filters = workspaceFilters(from: parsed)
        let workspaces = try fetchWorkspaces(in: context, filters: filters)
        let style = OutputStyle(useColor: shouldUseColor(flags: parsed.flags))
        if parsed.flags.contains("json") {
            let payload = WorkspaceListPayload(filters: filters, workspaces: workspaces.map(workspaceOutput))
            printJSON(payload)
            return
        }

        if workspaces.isEmpty {
            print("No workspaces found")
            return
        }

        printSectionTitle("Workspaces (\(workspaces.count))", style: style)
        printWorkspaceTable(workspaces, style: style)
    }

    static func handleWorkspaceNew(_ args: [String]) async throws {
        let parsed = try parseArguments(args)
        if parsed.flags.contains("help") {
            print(workspaceNewHelpText())
            return
        }
        guard parsed.positionals.count == 1 else {
            throw CLIError.invalidArguments("workspace new requires a name")
        }

        if let color = parsed.options["color"], !isValidHexColor(color) {
            throw CLIError.invalidArguments("Invalid color hex: \(color)")
        }

        let store = try CLIStore()
        let manager = CLIRepositoryManager(context: store.container.viewContext)
        let style = OutputStyle(useColor: shouldUseColor(flags: parsed.flags))
        let workspace = try manager.createWorkspace(name: parsed.positionals[0], colorHex: parsed.options["color"])
        print(style.success("Created workspace: \(workspace.name ?? "")"))
    }

    static func handleWorkspaceDelete(_ args: [String]) async throws {
        let parsed = try parseArguments(args)
        if parsed.flags.contains("help") {
            print(workspaceDeleteHelpText())
            return
        }
        guard parsed.positionals.count == 1 else {
            throw CLIError.invalidArguments("workspace delete requires a name")
        }

        let store = try CLIStore()
        let context = store.container.viewContext
        let manager = CLIRepositoryManager(context: context)
        let style = OutputStyle(useColor: shouldUseColor(flags: parsed.flags))

        guard let workspace = findWorkspace(named: parsed.positionals[0], in: context) else {
            throw CLIError.workspaceNotFound(parsed.positionals[0])
        }

        let repositories = (workspace.repositories as? Set<Repository>) ?? []
        if !parsed.flags.contains("force") {
            let promptMessage = "Delete workspace \"\(workspace.name ?? "")\" and remove \(repositories.count) repositories? [y/N]: "
            let response = prompt(promptMessage)?.lowercased() ?? ""
            if response != "y" && response != "yes" {
                print("Cancelled")
                return
            }
        }

        try manager.deleteWorkspace(workspace)
        print(style.success("Deleted workspace: \(workspace.name ?? "")"))
    }

    static func handleWorkspaceRename(_ args: [String]) async throws {
        let parsed = try parseArguments(args)
        if parsed.flags.contains("help") {
            print(workspaceRenameHelpText())
            return
        }
        guard parsed.positionals.count == 2 else {
            throw CLIError.invalidArguments("workspace rename requires old and new names")
        }

        let store = try CLIStore()
        let context = store.container.viewContext
        let manager = CLIRepositoryManager(context: context)
        let style = OutputStyle(useColor: shouldUseColor(flags: parsed.flags))

        guard let workspace = findWorkspace(named: parsed.positionals[0], in: context) else {
            throw CLIError.workspaceNotFound(parsed.positionals[0])
        }

        try manager.updateWorkspace(workspace, name: parsed.positionals[1])
        print(style.success("Renamed workspace to: \(parsed.positionals[1])"))
    }

    static func handleSync(_ args: [String]) async throws {
        let parsed = try parseArguments(args)
        if parsed.flags.contains("help") {
            print(syncHelpText())
            return
        }
        guard parsed.positionals.count <= 1 else {
            throw CLIError.invalidArguments("sync accepts at most one path argument")
        }

        let store = try CLIStore()
        let context = store.container.viewContext
        let manager = CLIRepositoryManager(context: context)
        let style = OutputStyle(useColor: shouldUseColor(flags: parsed.flags))

        let targetPath = parsed.positionals.first.map(normalizePath) ?? FileManager.default.currentDirectoryPath
        guard let repository = findRepository(for: targetPath, in: context) else {
            throw CLIError.repositoryNotFound(targetPath)
        }

        try await manager.refreshRepository(repository)
        print(style.success("Synced repository: \(repository.name ?? "")"))
    }

    static func handleStatus(_ args: [String]) async throws {
        let parsed = try parseArguments(args)
        if parsed.flags.contains("help") {
            print(statusHelpText())
            return
        }
        guard parsed.positionals.isEmpty else {
            throw CLIError.invalidArguments("status does not take arguments")
        }

        let store = try CLIStore()
        let context = store.container.viewContext
        let filters = workspaceFilters(from: parsed)

        let filteredWorkspaces = try fetchWorkspaces(in: context, filters: filters)
        let workspaceCount = filteredWorkspaces.count

        let repoFilters = RepositoryFilters(
            includeWorkspaces: filters.includeWorkspaces,
            excludeWorkspaces: filters.excludeWorkspaces,
            nameContains: nil,
            pathContains: nil
        )
        let filteredRepos = try fetchRepositories(in: context, filters: repoFilters)
        let repoCount = filteredRepos.count
        let worktreeCount = filteredRepos.reduce(0) { count, repo in
            count + ((repo.worktrees as? Set<Worktree>)?.count ?? 0)
        }

        let activeWorkspaceName = resolveActiveWorkspaceName(in: context)

        let includeSet = Set(filters.includeWorkspaces.map { $0.lowercased() })
        let excludeSet = Set(filters.excludeWorkspaces.map { $0.lowercased() })
        let recentRepos = fetchRecentRepositories(in: context, limit: 5)
            .filter { repo in
                guard let workspaceName = repo.workspace?.name else { return false }
                let lower = workspaceName.lowercased()
                if !includeSet.isEmpty, !includeSet.contains(lower) {
                    return false
                }
                if excludeSet.contains(lower) {
                    return false
                }
                return true
            }
        let style = OutputStyle(useColor: shouldUseColor(flags: parsed.flags))

        if parsed.flags.contains("json") {
            let payload = StatusPayload(
                workspaces: workspaceCount,
                repositories: repoCount,
                worktrees: worktreeCount,
                activeWorkspace: activeWorkspaceName,
                recentRepositories: recentRepos.map(repositoryOutput),
                filters: filters
            )
            printJSON(payload)
            return
        }

        printSectionTitle("Status", style: style)
        printKeyValue("Workspaces", "\(workspaceCount)", style: style)
        printKeyValue("Repositories", "\(repoCount)", style: style)
        printKeyValue("Worktrees", "\(worktreeCount)", style: style)
        printKeyValue("Active workspace", activeWorkspaceName ?? "-", style: style)

        if !recentRepos.isEmpty {
            print("")
            printSectionTitle("Recent repositories", style: style)
            for repo in recentRepos {
                let name = repo.name ?? ""
                let path = repo.path ?? ""
                print("- \(name) (\(path))")
            }
        }
    }
}

private extension AizenCLI {
    static func defaultCloneDestination() -> String {
        if let stored = readDefaultSetting(key: "defaultCloneLocation") {
            return stored
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return (home as NSString).appendingPathComponent(".aizen/repos")
    }

    static func ensureDirectoryExists(_ path: String) throws {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    static func isRemoteURL(_ value: String) -> Bool {
        if value.contains("://") {
            return true
        }
        if value.hasPrefix("git@"){ return true }
        if value.contains(":") && value.contains("@"){ return true }
        return false
    }

    static func ensureAizenGitignore(at repoPath: String) throws {
        let gitignorePath = (repoPath as NSString).appendingPathComponent(".gitignore")
        let entry = ".aizen/"
        if FileManager.default.fileExists(atPath: gitignorePath) {
            let contents = (try? String(contentsOfFile: gitignorePath, encoding: .utf8)) ?? ""
            if contents.split(separator: "\n").contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == entry }) {
                return
            }
            let updated = contents.hasSuffix("\n") || contents.isEmpty ? contents + entry + "\n" : contents + "\n" + entry + "\n"
            try updated.write(toFile: gitignorePath, atomically: true, encoding: .utf8)
        } else {
            try (entry + "\n").write(toFile: gitignorePath, atomically: true, encoding: .utf8)
        }
    }

    static func openApp(path: String? = nil) throws {
        let appURL = CLIStore.findAizenAppBundle()
        if appURL == nil {
            throw CLIError.appNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        if let path = path {
            let components = URLComponents(string: "aizen://open")
            var urlComponents = components ?? URLComponents()
            urlComponents.scheme = "aizen"
            urlComponents.host = "open"
            urlComponents.queryItems = [URLQueryItem(name: "path", value: path)]
            guard let url = urlComponents.url else {
                throw CLIError.invalidArguments("Invalid path")
            }
            if let appURL = appURL {
                process.arguments = ["-a", appURL.path, url.absoluteString]
            } else {
                process.arguments = [url.absoluteString]
            }
        } else if let appURL = appURL {
            process.arguments = ["-a", appURL.path]
        } else {
            process.arguments = ["-a", "Aizen"]
        }

        try process.run()
        process.waitUntilExit()
    }
}

private extension AizenCLI {
    static func fetchWorkspaces(in context: NSManagedObjectContext) throws -> [Workspace] {
        let request: NSFetchRequest<Workspace> = Workspace.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Workspace.order, ascending: true)]
        return try context.fetch(request)
    }

    static func fetchWorkspaces(in context: NSManagedObjectContext, filters: WorkspaceFilters) throws -> [Workspace] {
        let all = try fetchWorkspaces(in: context)
        let includeList = filters.includeWorkspaces
        let excludeList = filters.excludeWorkspaces
        let include = Set(includeList.map { $0.lowercased() })
        let exclude = Set(excludeList.map { $0.lowercased() })

        for name in includeList {
            if !all.contains(where: { ($0.name ?? "").lowercased() == name.lowercased() }) {
                throw CLIError.workspaceNotFound(name)
            }
        }
        for name in excludeList {
            if !all.contains(where: { ($0.name ?? "").lowercased() == name.lowercased() }) {
                throw CLIError.workspaceNotFound(name)
            }
        }

        let nameContains = filters.nameContains?.lowercased()
        return all.filter { workspace in
            let name = (workspace.name ?? "")
            let lower = name.lowercased()
            if !include.isEmpty && !include.contains(lower) {
                return false
            }
            if exclude.contains(lower) {
                return false
            }
            if let nameContains = nameContains, !name.lowercased().contains(nameContains) {
                return false
            }
            return true
        }
    }

    static func findWorkspace(named name: String, in context: NSManagedObjectContext) -> Workspace? {
        let request: NSFetchRequest<Workspace> = Workspace.fetchRequest()
        request.predicate = NSPredicate(format: "name ==[c] %@", name)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    static func selectWorkspace(
        in context: NSManagedObjectContext,
        preferredName: String?,
        defaultWorkspaceId: String?
    ) throws -> Workspace {
        let workspaces = try fetchWorkspaces(in: context)
        if workspaces.isEmpty {
            let manager = CLIRepositoryManager(context: context)
            return try manager.createWorkspace(name: "Personal")
        }

        if let preferredName = preferredName {
            if let workspace = findWorkspace(named: preferredName, in: context) {
                return workspace
            }
            throw CLIError.workspaceNotFound(preferredName)
        }

        if let defaultWorkspaceId = defaultWorkspaceId,
           let uuid = UUID(uuidString: defaultWorkspaceId) {
            if let workspace = workspaces.first(where: { $0.id == uuid }) {
                return workspace
            }
        }

        if workspaces.count == 1 {
            return workspaces[0]
        }

        guard isTTY() else {
            throw CLIError.invalidArguments("Workspace is required when running non-interactively")
        }

        print("Select workspace:")
        for (index, workspace) in workspaces.enumerated() {
            let name = workspace.name ?? ""
            print("  [\(index + 1)] \(name)")
        }

        let selection = prompt("Enter number: ")
        if let selection = selection, let index = Int(selection), index > 0, index <= workspaces.count {
            return workspaces[index - 1]
        }

        throw CLIError.invalidArguments("Invalid workspace selection")
    }

    static func fetchRepositories(in context: NSManagedObjectContext, filters: RepositoryFilters) throws -> [Repository] {
        let request: NSFetchRequest<Repository> = Repository.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Repository.name, ascending: true)]
        let all = try context.fetch(request)
        let includeList = filters.includeWorkspaces
        let excludeList = filters.excludeWorkspaces
        let include = Set(includeList.map { $0.lowercased() })
        let exclude = Set(excludeList.map { $0.lowercased() })
        let nameContains = filters.nameContains?.lowercased()
        let pathContains = filters.pathContains?.lowercased()

        if !include.isEmpty || !exclude.isEmpty {
            let workspaces = try fetchWorkspaces(in: context)
            let workspaceNames = Set(workspaces.compactMap { $0.name?.lowercased() })
            for name in includeList where !workspaceNames.contains(name.lowercased()) {
                throw CLIError.workspaceNotFound(name)
            }
            for name in excludeList where !workspaceNames.contains(name.lowercased()) {
                throw CLIError.workspaceNotFound(name)
            }
        }

        return all.filter { repo in
            let workspaceName = repo.workspace?.name?.lowercased() ?? ""
            if !include.isEmpty && !include.contains(workspaceName) {
                return false
            }
            if exclude.contains(workspaceName) {
                return false
            }
            if let nameContains = nameContains {
                let name = (repo.name ?? "").lowercased()
                if !name.contains(nameContains) {
                    return false
                }
            }
            if let pathContains = pathContains {
                let path = (repo.path ?? "").lowercased()
                if !path.contains(pathContains) {
                    return false
                }
            }
            return true
        }
    }

    static func findRepository(for path: String, in context: NSManagedObjectContext) -> Repository? {
        let normalized = normalizePath(path)

        let worktreeRequest: NSFetchRequest<Worktree> = Worktree.fetchRequest()
        worktreeRequest.predicate = NSPredicate(format: "path == %@", normalized)
        worktreeRequest.fetchLimit = 1
        if let worktree = try? context.fetch(worktreeRequest).first,
           let repository = worktree.repository {
            return repository
        }

        let repoRequest: NSFetchRequest<Repository> = Repository.fetchRequest()
        repoRequest.predicate = NSPredicate(format: "path == %@", normalized)
        repoRequest.fetchLimit = 1
        if let repo = try? context.fetch(repoRequest).first {
            return repo
        }

        let allRequest: NSFetchRequest<Repository> = Repository.fetchRequest()
        guard let allRepos = try? context.fetch(allRequest) else {
            return nil
        }

        var bestMatch: Repository?
        var bestLength = 0
        for repo in allRepos {
            guard let repoPath = repo.path else { continue }
            if normalized == repoPath || normalized.hasPrefix(repoPath + "/") {
                if repoPath.count > bestLength {
                    bestLength = repoPath.count
                    bestMatch = repo
                }
            }
        }

        return bestMatch
    }

    static func resolveActiveWorkspaceName(in context: NSManagedObjectContext) -> String? {
        let bundleIds = ["win.aizen.app", "win.aizen.app.nightly"]
        for bundleId in bundleIds {
            let defaults = UserDefaults(suiteName: bundleId)
            guard let idString = defaults?.string(forKey: "selectedWorkspaceId"),
                  let uuid = UUID(uuidString: idString) else {
                continue
            }
            let request: NSFetchRequest<Workspace> = Workspace.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
            request.fetchLimit = 1
            if let workspace = (try? context.fetch(request))?.first,
               let name = workspace.name {
                return name
            }
        }
        return nil
    }

    static func readDefaultSetting(key: String) -> String? {
        let bundleIds = ["win.aizen.app", "win.aizen.app.nightly"]
        for bundleId in bundleIds {
            if let value = UserDefaults(suiteName: bundleId)?.string(forKey: key),
               !value.isEmpty {
                return value
            }
            if let value = readContainerPreference(bundleId: bundleId, key: key),
               !value.isEmpty {
                return value
            }
        }
        return nil
    }

    static func readContainerPreference(bundleId: String, key: String) -> String? {
        let fileManager = FileManager.default
        let plistURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers")
            .appendingPathComponent(bundleId)
            .appendingPathComponent("Data/Library/Preferences")
            .appendingPathComponent("\(bundleId).plist")
        guard let data = try? Data(contentsOf: plistURL) else { return nil }
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return nil
        }
        return plist[key] as? String
    }

    static func fetchRecentRepositories(in context: NSManagedObjectContext, limit: Int) -> [Repository] {
        let request: NSFetchRequest<Worktree> = Worktree.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Worktree.lastAccessed, ascending: false)]
        request.fetchLimit = 50

        guard let worktrees = try? context.fetch(request) else { return [] }

        var seen = Set<NSManagedObjectID>()
        var repos: [Repository] = []

        for worktree in worktrees {
            guard let repo = worktree.repository else { continue }
            let id = repo.objectID
            if seen.contains(id) { continue }
            seen.insert(id)
            repos.append(repo)
            if repos.count >= limit { break }
        }

        return repos
    }
}

private extension AizenCLI {
    struct RepositoryOutput: Encodable {
        let name: String
        let path: String
        let workspace: String?
        let worktrees: Int
        let updated: String?
    }

    struct RepositoryFilters: Encodable {
        let includeWorkspaces: [String]
        let excludeWorkspaces: [String]
        let nameContains: String?
        let pathContains: String?
    }

    struct RepositoryListPayload: Encodable {
        let filters: RepositoryFilters
        let repositories: [RepositoryOutput]
    }

    struct WorkspaceOutput: Encodable {
        let name: String
        let color: String?
        let repositories: Int
        let order: Int
    }

    struct WorkspaceFilters: Encodable {
        let includeWorkspaces: [String]
        let excludeWorkspaces: [String]
        let nameContains: String?
    }

    struct WorkspaceListPayload: Encodable {
        let filters: WorkspaceFilters
        let workspaces: [WorkspaceOutput]
    }

    struct StatusPayload: Encodable {
        let workspaces: Int
        let repositories: Int
        let worktrees: Int
        let activeWorkspace: String?
        let recentRepositories: [RepositoryOutput]
        let filters: WorkspaceFilters
    }

    static func printRepositoryTable(_ repositories: [Repository], style: OutputStyle) {
        let headers = ["Repository", "Path", "Workspace", "Worktrees", "Updated"]
        var rows: [[String]] = []
        for repo in repositories {
            let name = repo.name ?? ""
            let path = repo.path ?? ""
            let workspace = repo.workspace?.name ?? "-"
            let worktreeCount = String((repo.worktrees as? Set<Worktree>)?.count ?? 0)
            let updated = formatDate(repo.lastUpdated)
            rows.append([name, path, workspace, worktreeCount, updated])
        }
        printTable(headers: headers, rows: rows, style: style)
    }

    static func printWorkspaceTable(_ workspaces: [Workspace], style: OutputStyle) {
        let headers = ["Workspace", "Color", "Repositories", "Order"]
        var rows: [[String]] = []
        for workspace in workspaces {
            let name = workspace.name ?? ""
            let color = workspace.colorHex ?? "-"
            let repoCount = String((workspace.repositories as? Set<Repository>)?.count ?? 0)
            let order = String(workspace.order)
            rows.append([name, color, repoCount, order])
        }
        printTable(headers: headers, rows: rows, style: style)
    }

    static func printTable(headers: [String], rows: [[String]], style: OutputStyle) {
        var widths = headers.map { $0.count }
        for row in rows {
            for (index, value) in row.enumerated() {
                if value.count > widths[index] {
                    widths[index] = value.count
                }
            }
        }

        func pad(_ text: String, _ width: Int) -> String {
            let padding = max(0, width - text.count)
            return text + String(repeating: " ", count: padding)
        }

        let headerLine = zip(headers, widths).map { pad($0, $1) }.joined(separator: "  ")
        print(style.header(headerLine))
        let separator = widths.map { String(repeating: "-", count: $0) }.joined(separator: "  ")
        print(style.label(separator))
        for row in rows {
            let line = zip(row, widths).map { pad($0, $1) }.joined(separator: "  ")
            print(line)
        }
    }

    static func printSectionTitle(_ title: String, style: OutputStyle) {
        if isStdoutTTY() {
            print(style.section("== \(title)"))
        } else {
            print(title)
        }
    }

    static func printKeyValue(_ key: String, _ value: String, style: OutputStyle) {
        let paddedKey = key.padding(toLength: 16, withPad: " ", startingAt: 0)
        print("\(style.label(paddedKey)) \(value)")
    }

    static func repositoryOutput(_ repo: Repository) -> RepositoryOutput {
        let updated = iso8601Date(repo.lastUpdated)
        return RepositoryOutput(
            name: repo.name ?? "",
            path: repo.path ?? "",
            workspace: repo.workspace?.name,
            worktrees: (repo.worktrees as? Set<Worktree>)?.count ?? 0,
            updated: updated
        )
    }

    static func workspaceOutput(_ workspace: Workspace) -> WorkspaceOutput {
        WorkspaceOutput(
            name: workspace.name ?? "",
            color: workspace.colorHex,
            repositories: (workspace.repositories as? Set<Repository>)?.count ?? 0,
            order: Int(workspace.order)
        )
    }

    static func iso8601Date(_ date: Date?) -> String? {
        guard let date = date else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    static func printJSON<T: Encodable>(_ payload: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(payload),
           let output = String(data: data, encoding: .utf8) {
            print(output)
        }
    }

    static func repositoryFilters(from parsed: ParsedArguments, positionalWorkspace: String?) -> RepositoryFilters {
        var include = Set(splitList(parsed.options["workspace"]))
        if let positionalWorkspace = positionalWorkspace, !positionalWorkspace.isEmpty {
            include.insert(positionalWorkspace)
        }
        let exclude = Set(splitList(parsed.options["exclude-workspace"]))
        let name = parsed.options["name"]
        let path = parsed.options["path"]
        return RepositoryFilters(
            includeWorkspaces: include.sorted(),
            excludeWorkspaces: exclude.sorted(),
            nameContains: name,
            pathContains: path
        )
    }

    static func workspaceFilters(from parsed: ParsedArguments) -> WorkspaceFilters {
        let include = Set(splitList(parsed.options["workspace"]))
        let exclude = Set(splitList(parsed.options["exclude-workspace"]))
        let name = parsed.options["name"]
        return WorkspaceFilters(
            includeWorkspaces: include.sorted(),
            excludeWorkspaces: exclude.sorted(),
            nameContains: name
        )
    }

    static func splitList(_ value: String?) -> [String] {
        guard let value = value, !value.isEmpty else { return [] }
        return value.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private extension AizenCLI {
    static func helpText() -> String {
        return """
Aizen CLI

Usage:
  aizen
  aizen open [path]
  aizen add [path|url] [--workspace <name>] [--destination <path>]
  aizen remove <path>
  aizen list [workspace]
  aizen ls [workspace]
  aizen workspace <command>
  aizen ws <command>
  aizen sync [path]
  aizen status

Run 'aizen <command> --help' for more details.
"""
    }

    static func addHelpText() -> String {
        return """
Usage:
  aizen add [path|url] [--workspace <name>] [--destination <path>]

Adds an existing repo or clones a remote repo and tracks it.
"""
    }

    static func removeHelpText() -> String {
        return """
Usage:
  aizen remove <path>

Removes a repository from tracking.
"""
    }

    static func listHelpText() -> String {
        return """
Usage:
  aizen list [workspace]
  aizen ls [workspace]

Lists tracked repositories.

Options:
  -w, --workspace <name>         Filter by workspace (comma-separated)
  --exclude-workspace <name>     Exclude workspace(s) (comma-separated)
  --name <text>                  Filter by repository name
  --path <text>                  Filter by repository path
  --json                         Output JSON
  --no-color                     Disable colored output
"""
    }

    static func workspaceListHelpText() -> String {
        return """
Usage:
  aizen workspace list
  aizen ws list

Options:
  -w, --workspace <name>         Include workspace(s) (comma-separated)
  --name <text>                  Filter by workspace name
  --exclude-workspace <name>     Exclude workspace(s) (comma-separated)
  --json                         Output JSON
  --no-color                     Disable colored output
"""
    }

    static func workspaceNewHelpText() -> String {
        return """
Usage:
  aizen workspace new <name> [--color <hex>]
  aizen ws new <name> [--color <hex>]
"""
    }

    static func workspaceDeleteHelpText() -> String {
        return """
Usage:
  aizen workspace delete <name> [--force]
  aizen ws delete <name> [--force]
"""
    }

    static func workspaceRenameHelpText() -> String {
        return """
Usage:
  aizen workspace rename <old-name> <new-name>
  aizen ws rename <old-name> <new-name>
"""
    }

    static func syncHelpText() -> String {
        return """
Usage:
  aizen sync [path]

Rescans worktrees for a repository and updates the database.
"""
    }

    static func statusHelpText() -> String {
        return """
Usage:
  aizen status

Shows overview of Aizen's current state.

Options:
  -w, --workspace <name>         Limit counts to workspace(s) (comma-separated)
  --exclude-workspace <name>     Exclude workspace(s) (comma-separated)
  --json                         Output JSON
  --no-color                     Disable colored output
"""
    }

    static func openHelpText() -> String {
        return """
Usage:
  aizen open [path]

Opens the Aizen GUI. If a path is provided, focuses the tracked repository.
"""
    }

    static func workspaceHelpText() -> String {
        return """
Usage:
  aizen workspace list
  aizen workspace new <name> [--color <hex>]
  aizen workspace delete <name> [--force]
  aizen workspace rename <old-name> <new-name>
"""
    }
}
