import AizenCore
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
        case "--version", "version":
            try await handleVersion(subArgs)
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
        case "space":
            try await handleWorkspace(subArgs)
        case "conversation":
            try await handleConversation(subArgs)
        case "session":
            try await handleConversation(subArgs)
        case "run":
            try await handleRun(subArgs)
        case "resource":
            try await handleResource(subArgs)
        case "context":
            try await handleExecutionContext(subArgs)
        case "sync":
            try await handleSync(subArgs)
        case "status":
            try await handleStatus(subArgs)
        case "attach":
            try await handleAttach(subArgs)
        case "sessions":
            try await handleSessions(subArgs)
        case "terminal":
            try await handleTerminal(subArgs)
        default:
            throw CLIError.invalidArguments("Unknown command: \(command)")
        }
    }
}

private extension AizenCLI {
    static func handleVersion(_ args: [String]) async throws {
        guard args.isEmpty else { throw CLIError.invalidArguments("version does not take arguments") }
        let capabilities = try await V2CLIClient().compatibility()
        print("Aizen CLI \(V2CLIClient.productVersion)")
        print("Host \(capabilities.productVersion)")
        print("Protocol generation \(capabilities.minimumProtocolGeneration)...\(capabilities.maximumProtocolGeneration)")
        print("Minimum compatible product \(capabilities.minimumCompatibleProductVersion)")
    }

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

        guard FileManager.default.fileExists(atPath: path) else {
            throw CLIError.pathNotFound(path)
        }

        let canonicalPath = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
        let client = V2CLIClient()
        if try await client.resources().contains(where: {
            guard case let .hostPrivate(reference) = $0.details else { return false }
            return reference.rawValue == "local-repository:\(canonicalPath)"
        }) {
            try openApp(path: path)
            return
        }

        guard await GitUtils.isGitRepository(at: path) else {
            throw CLIError.notGitRepository(path)
        }

        throw CLIError.repositoryNotFound(path)
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

        let style = OutputStyle(useColor: shouldUseColor(flags: parsed.flags))

        let target = parsed.positionals.first ?? FileManager.default.currentDirectoryPath
        guard !isRemoteURL(target) else {
            throw CLIError.invalidArguments("Remote clone is not available through the v2 Host yet; clone locally, then run 'aizen resource add-repository'.")
        }
        let path = normalizePath(target)
        guard FileManager.default.fileExists(atPath: path) else { throw CLIError.pathNotFound(path) }
        guard await GitUtils.isGitRepository(at: path) else { throw CLIError.notGitRepository(path) }

        let client = V2CLIClient()
        let spaces = try await client.spaces()
        let space: Space
        if let name = parsed.options["workspace"] {
            guard let match = spaces.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                throw CLIError.workspaceNotFound(name)
            }
            space = match
        } else if spaces.count == 1, let onlySpace = spaces.first {
            space = onlySpace
        } else {
            throw CLIError.invalidArguments("Specify --workspace <space>; v2 does not use a hidden default workspace.")
        }
        _ = try await client.importLocalRepository(spaceID: space.id, path: path)
        print(style.success("Added repository: \(URL(fileURLWithPath: path).lastPathComponent)"))
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

        let style = OutputStyle(useColor: shouldUseColor(flags: parsed.flags))

        let path = normalizePath(parsed.positionals[0])
        let canonicalPath = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
        let client = V2CLIClient()
        guard let resource = try await client.resources().first(where: {
            guard case let .hostPrivate(reference) = $0.details else { return false }
            return reference.rawValue == "local-repository:\(canonicalPath)"
        }) else {
            throw CLIError.repositoryNotFound(path)
        }

        try await client.removeResource(id: resource.id)
        print(style.success("Removed repository: \(resource.title)"))
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

        let workspaceFilter = parsed.positionals.first
        let filters = repositoryFilters(from: parsed, positionalWorkspace: workspaceFilter)
        guard filters.pathContains == nil else {
            throw CLIError.invalidArguments("--path is unavailable because v2 Resources do not expose host paths")
        }
        let resources = try await v2Resources(filters: filters)
        let style = OutputStyle(useColor: shouldUseColor(flags: parsed.flags))

        if parsed.flags.contains("json") {
            printJSON(ResourceListPayload(filters: filters, resources: resources.map(resourceOutput)))
            return
        }

        if resources.isEmpty {
            if !filters.includeWorkspaces.isEmpty {
                let names = filters.includeWorkspaces.sorted().joined(separator: ", ")
                print("No resources found in workspace(s): \(names)")
            } else {
                print("No resources found")
            }
            return
        }

        let title = filters.includeWorkspaces.isEmpty
            ? "Resources (\(resources.count))"
            : "Resources (\(resources.count)) in \(filters.includeWorkspaces.joined(separator: ", "))"
        printSectionTitle(title, style: style)
        printResourceTable(resources, style: style)
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

    static func handleConversation(_ args: [String]) async throws {
        guard let subcommand = args.first else {
            throw CLIError.invalidArguments("conversation requires list, new, show, or send")
        }
        let rest = Array(args.dropFirst())
        switch subcommand {
        case "list":
            guard rest.count <= 1 else { throw CLIError.invalidArguments("conversation list accepts at most one space") }
            let client = V2CLIClient()
            let spaceID = try await resolveV2Space(rest.first, client: client)
            for conversation in try await client.conversations(spaceID: spaceID) {
                print("\(conversation.id.description)\t\(conversation.title)")
            }
        case "new":
            guard rest.count >= 2 else { throw CLIError.invalidArguments("conversation new requires a space and title") }
            let client = V2CLIClient()
            let spaceID = try await resolveV2Space(rest[0], client: client)
            guard let spaceID else { throw CLIError.invalidArguments("conversation new requires a space") }
            let title = rest.dropFirst().joined(separator: " ")
            let sessionID = try await client.createConversation(spaceID: spaceID, title: title)
            print(sessionID.description)
        case "show":
            guard rest.count == 1, let sessionUUID = UUID(uuidString: rest[0]) else {
                throw CLIError.invalidArguments("conversation show requires a Session ID")
            }
            let client = V2CLIClient()
            let messages = try await client.conversationTimeline(sessionID: SessionID(rawValue: sessionUUID))
            for message in messages {
                print("\(message.role.rawValue)\t\(message.content)")
            }
        case "send":
            guard rest.count >= 2, let sessionUUID = UUID(uuidString: rest[0]) else {
                throw CLIError.invalidArguments("conversation send requires a Session ID and message")
            }
            let client = V2CLIClient()
            let sessionID = SessionID(rawValue: sessionUUID)
            guard let conversation = try await client.conversations().first(where: { $0.id == sessionID }) else {
                throw CLIError.sessionNotFound(rest[0])
            }
            let runID = try await client.sendConversation(
                spaceID: conversation.spaceID,
                sessionID: sessionID,
                content: rest.dropFirst().joined(separator: " ")
            )
            print(runID.description)
        default:
            throw CLIError.invalidArguments("Unknown conversation command: \(subcommand)")
        }
    }

    static func resolveV2Space(_ value: String?, client: V2CLIClient) async throws -> SpaceID? {
        guard let value else { return nil }
        if let uuid = UUID(uuidString: value) { return SpaceID(rawValue: uuid) }
        guard let space = try await client.spaces().first(where: { $0.name.caseInsensitiveCompare(value) == .orderedSame }) else {
            throw CLIError.workspaceNotFound(value)
        }
        return space.id
    }

    static func handleRun(_ args: [String]) async throws {
        guard let subcommand = args.first else {
            throw CLIError.invalidArguments("run requires list or cancel")
        }
        let rest = Array(args.dropFirst())
        let client = V2CLIClient()
        switch subcommand {
        case "list":
            guard rest.count <= 1 else { throw CLIError.invalidArguments("run list accepts at most one space") }
            let spaceID = try await resolveV2Space(rest.first, client: client)
            for run in try await client.runs(spaceID: spaceID) {
                print("\(run.id.description)\t\(run.lifecycle.rawValue)\t\(run.sessionID.description)")
            }
        case "cancel":
            guard rest.count == 1, let runUUID = UUID(uuidString: rest[0]) else {
                throw CLIError.invalidArguments("run cancel requires a Run ID")
            }
            try await client.cancelRun(id: RunID(rawValue: runUUID))
        default:
            throw CLIError.invalidArguments("Unknown run command: \(subcommand)")
        }
    }

    static func handleResource(_ args: [String]) async throws {
        guard let subcommand = args.first else {
            throw CLIError.invalidArguments("resource requires list, add, add-repository, or remove")
        }
        let rest = Array(args.dropFirst())
        let client = V2CLIClient()
        switch subcommand {
        case "list":
            guard rest.count <= 1 else { throw CLIError.invalidArguments("resource list accepts at most one space") }
            let spaceID = try await resolveV2Space(rest.first, client: client)
            for resource in try await client.resources(spaceID: spaceID) {
                print("\(resource.id.description)\t\(resource.kind.rawValue)\t\(resource.title)")
            }
        case "add":
            guard rest.count >= 2 else { throw CLIError.invalidArguments("resource add requires a space and absolute folder path") }
            let spaceID = try await resolveV2Space(rest[0], client: client)
            guard let spaceID else { throw CLIError.invalidArguments("resource add requires a space") }
            let path = rest[1]
            let title = rest.count > 2 ? rest.dropFirst(2).joined(separator: " ") : nil
            print(try await client.importLocalFolder(spaceID: spaceID, path: path, title: title).description)
        case "add-repository":
            guard rest.count >= 2 else { throw CLIError.invalidArguments("resource add-repository requires a space and absolute repository path") }
            let spaceID = try await resolveV2Space(rest[0], client: client)
            guard let spaceID else { throw CLIError.invalidArguments("resource add-repository requires a space") }
            let title = rest.count > 2 ? rest.dropFirst(2).joined(separator: " ") : nil
            print(try await client.importLocalRepository(spaceID: spaceID, path: rest[1], title: title).description)
        case "remove":
            guard rest.count == 1, let uuid = UUID(uuidString: rest[0]) else {
                throw CLIError.invalidArguments("resource remove requires a Resource ID")
            }
            try await client.removeResource(id: ResourceID(rawValue: uuid))
        default:
            throw CLIError.invalidArguments("Unknown resource command: \(subcommand)")
        }
    }

    static func handleExecutionContext(_ args: [String]) async throws {
        guard let subcommand = args.first else {
            throw CLIError.invalidArguments("context requires list, create, create-checkout, attach, detach, or remove")
        }
        let rest = Array(args.dropFirst())
        let client = V2CLIClient()
        switch subcommand {
        case "list":
            guard rest.count <= 1 else { throw CLIError.invalidArguments("context list accepts at most one space") }
            let spaceID = try await resolveV2Space(rest.first, client: client)
            for context in try await client.executionContexts(spaceID: spaceID) {
                print("\(context.id.description)\t\(context.kind.rawValue)\t\(context.resourceID?.description ?? "-")")
            }
        case "create":
            guard rest.count == 2, let resourceUUID = UUID(uuidString: rest[1]) else {
                throw CLIError.invalidArguments("context create requires a space and Resource ID")
            }
            let spaceID = try await resolveV2Space(rest[0], client: client)
            guard let spaceID else { throw CLIError.invalidArguments("context create requires a space") }
            print(try await client.createLocalFolderContext(spaceID: spaceID, resourceID: ResourceID(rawValue: resourceUUID)).description)
        case "attach":
            guard rest.count == 2,
                let sessionUUID = UUID(uuidString: rest[0]),
                let contextUUID = UUID(uuidString: rest[1]) else {
                throw CLIError.invalidArguments("context attach requires a Session ID and Context ID")
            }
            try await client.attachExecutionContext(
                sessionID: SessionID(rawValue: sessionUUID),
                contextID: ExecutionContextID(rawValue: contextUUID)
            )
        case "create-checkout":
            guard rest.count == 2, let resourceUUID = UUID(uuidString: rest[1]) else {
                throw CLIError.invalidArguments("context create-checkout requires a space and Resource ID")
            }
            let spaceID = try await resolveV2Space(rest[0], client: client)
            guard let spaceID else { throw CLIError.invalidArguments("context create-checkout requires a space") }
            print(try await client.createRepositoryCheckoutContext(spaceID: spaceID, resourceID: ResourceID(rawValue: resourceUUID)).description)
        case "remove":
            guard rest.count == 1, let contextUUID = UUID(uuidString: rest[0]) else {
                throw CLIError.invalidArguments("context remove requires a Context ID")
            }
            try await client.removeExecutionContext(id: ExecutionContextID(rawValue: contextUUID))
        case "detach":
            guard rest.count == 1, let sessionUUID = UUID(uuidString: rest[0]) else {
                throw CLIError.invalidArguments("context detach requires a Session ID")
            }
            try await client.detachExecutionContext(sessionID: SessionID(rawValue: sessionUUID))
        default:
            throw CLIError.invalidArguments("Unknown context command: \(subcommand)")
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

        let filters = workspaceFilters(from: parsed)
        let workspaces = try await v2Workspaces(filters: filters)
        let style = OutputStyle(useColor: shouldUseColor(flags: parsed.flags))
        if parsed.flags.contains("json") {
            let payload = WorkspaceListPayload(filters: filters, workspaces: workspaces.enumerated().map(workspaceOutput))
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

        let style = OutputStyle(useColor: shouldUseColor(flags: parsed.flags))
        try await V2CLIClient().createSpace(name: parsed.positionals[0], icon: parsed.options["color"])
        print(style.success("Created workspace: \(parsed.positionals[0])"))
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

        let style = OutputStyle(useColor: shouldUseColor(flags: parsed.flags))
        let client = V2CLIClient()

        guard let workspace = try await client.spaces().first(where: { $0.name.caseInsensitiveCompare(parsed.positionals[0]) == .orderedSame }) else {
            throw CLIError.workspaceNotFound(parsed.positionals[0])
        }

        if !parsed.flags.contains("force") {
            let promptMessage = "Delete workspace \"\(workspace.name)\"? [y/N]: "
            let response = prompt(promptMessage)?.lowercased() ?? ""
            if response != "y" && response != "yes" {
                print("Cancelled")
                return
            }
        }

        try await client.deleteSpace(id: workspace.id)
        print(style.success("Deleted workspace: \(workspace.name)"))
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

        let style = OutputStyle(useColor: shouldUseColor(flags: parsed.flags))
        let client = V2CLIClient()

        guard let workspace = try await client.spaces().first(where: { $0.name.caseInsensitiveCompare(parsed.positionals[0]) == .orderedSame }) else {
            throw CLIError.workspaceNotFound(parsed.positionals[0])
        }

        try await client.renameSpace(id: workspace.id, name: parsed.positionals[1])
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

        let style = OutputStyle(useColor: shouldUseColor(flags: parsed.flags))

        let targetPath = parsed.positionals.first.map(normalizePath) ?? FileManager.default.currentDirectoryPath
        let canonicalPath = URL(fileURLWithPath: targetPath).standardizedFileURL.resolvingSymlinksInPath().path
        let client = V2CLIClient()
        guard let resource = try await client.resources().first(where: {
            guard case let .hostPrivate(reference) = $0.details else { return false }
            return reference.rawValue == "local-repository:\(canonicalPath)"
        }) else {
            throw CLIError.repositoryNotFound(targetPath)
        }

        try await client.refreshRepositoryResource(id: resource.id)
        print(style.success("Synced repository: \(resource.title)"))
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

        let filters = workspaceFilters(from: parsed)
        let spaces = try await v2Workspaces(filters: filters)
        let spaceIDs = Set(spaces.map(\.id))
        let client = V2CLIClient()
        async let resources = client.resources()
        async let contexts = client.executionContexts()
        async let conversations = client.conversations()
        async let runs = client.runs()
        let (allResources, allContexts, allConversations, allRuns) = try await (resources, contexts, conversations, runs)
        let resourceCount = allResources.count(where: { spaceIDs.contains($0.spaceID) })
        let contextCount = allContexts.count(where: { spaceIDs.contains($0.spaceID) })
        let conversationCount = allConversations.count(where: { spaceIDs.contains($0.spaceID) })
        let runCount = allRuns.count(where: { spaceIDs.contains($0.spaceID) })
        let style = OutputStyle(useColor: shouldUseColor(flags: parsed.flags))

        if parsed.flags.contains("json") {
            let payload = StatusPayload(
                spaces: spaces.count,
                resources: resourceCount,
                executionContexts: contextCount,
                conversations: conversationCount,
                runs: runCount,
                filters: filters
            )
            printJSON(payload)
            return
        }

        printSectionTitle("Status", style: style)
        printKeyValue("Spaces", "\(spaces.count)", style: style)
        printKeyValue("Resources", "\(resourceCount)", style: style)
        printKeyValue("Contexts", "\(contextCount)", style: style)
        printKeyValue("Conversations", "\(conversationCount)", style: style)
        printKeyValue("Runs", "\(runCount)", style: style)
    }

    static func handleAttach(_ args: [String]) async throws {
        let parsed = try parseArguments(args)
        if parsed.flags.contains("help") {
            print(attachHelpText())
            return
        }
        guard !parsed.flags.contains("cross-project") else {
            throw CLIError.invalidArguments("Cross-project terminals are not available through the v2 Host yet.")
        }
        guard parsed.options["worktree"] == nil else {
            throw CLIError.invalidArguments("Worktree filtering is not available for v2 Host-owned terminals.")
        }

        let client = V2CLIClient()
        let spaces = try await client.spaces()
        let selectedSpace: Space?
        if let name = parsed.options["workspace"] {
            guard let space = spaces.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                throw CLIError.workspaceNotFound(name)
            }
            selectedSpace = space
        } else {
            selectedSpace = nil
        }
        var sessions = try await client.terminalSessions(spaceID: selectedSpace?.id)
        if let selector = parsed.positionals.first?.lowercased() {
            sessions = sessions.filter {
                $0.id.description.lowercased().hasPrefix(selector)
                    || ($0.title?.lowercased().contains(selector) ?? false)
            }
        }
        guard !sessions.isEmpty else { throw CLIError.noActiveSessions }
        guard sessions.count == 1, let terminal = sessions.first else {
            throw CLIError.invalidArguments("Multiple Host-owned terminals match. Specify a terminal title or session ID prefix, and use --workspace to filter.")
        }
        guard tmuxSessionExists(sessionName: terminal.tmuxSessionName) else {
            throw CLIError.sessionNotFound(terminal.title ?? terminal.id.description)
        }
        print(OutputStyle(useColor: shouldUseColor(flags: parsed.flags)).success("Attaching to: \(terminal.title ?? terminal.id.description)"))
        try tmuxAttach(sessionName: terminal.tmuxSessionName)
    }

    static func handleSessions(_ args: [String]) async throws {
        let parsed = try parseArguments(args)
        if parsed.flags.contains("help") {
            print(sessionsHelpText())
            return
        }

        let style = OutputStyle(useColor: shouldUseColor(flags: parsed.flags))
        guard !parsed.flags.contains("cross-project") else {
            throw CLIError.invalidArguments("Cross-project terminal sessions are not available through the v2 Host yet.")
        }
        let client = V2CLIClient()
        let spaces = try await client.spaces()
        let spacesByID = Dictionary(uniqueKeysWithValues: spaces.map { ($0.id, $0.name) })
        let selectedSpace = try parsed.options["workspace"].map { name -> SpaceID in
            guard let space = spaces.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                throw CLIError.workspaceNotFound(name)
            }
            return space.id
        }
        let sessions = try await client.terminalSessions(spaceID: selectedSpace)

        if parsed.flags.contains("json") {
            let payload = TerminalSessionListPayload(sessions: sessions.map { session in
                TerminalSessionOutput(
                    id: session.id.description,
                    space: spacesByID[session.spaceID] ?? session.spaceID.description,
                    title: session.title ?? "",
                    tmuxSession: session.tmuxSessionName,
                    paneID: session.paneID
                )
            })
            printJSON(payload)
            return
        }

        if sessions.isEmpty {
            print("No active terminal sessions found")
            if !isTmuxAvailable() {
                print(style.warning("Note: tmux is not installed. Install with: brew install tmux"))
            }
            return
        }

        printSectionTitle("Terminal Sessions (\(sessions.count))", style: style)
        let headers = ["Space", "Title", "tmux Session", "Pane"]
        let rows = sessions.map { session in
            [spacesByID[session.spaceID] ?? session.spaceID.description, session.title ?? "-", session.tmuxSessionName, session.paneID]
        }
        printTable(headers: headers, rows: rows, style: style)
    }

    static func handleTerminal(_ args: [String]) async throws {
        let parsed = try parseArguments(args)
        if parsed.flags.contains("help") {
            print(terminalHelpText())
            return
        }
        guard !parsed.flags.contains("cross-project") else {
            throw CLIError.invalidArguments("Cross-project terminals are not available through the v2 Host yet.")
        }

        let targetPath = parsed.positionals.first.map(normalizePath) ?? FileManager.default.currentDirectoryPath
        guard FileManager.default.fileExists(atPath: targetPath) else { throw CLIError.pathNotFound(targetPath) }
        guard await GitUtils.isGitRepository(at: targetPath) else { throw CLIError.notGitRepository(targetPath) }

        let client = V2CLIClient()
        let spaces = try await client.spaces()
        let space: Space
        if let name = parsed.options["workspace"] {
            guard let match = spaces.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                throw CLIError.workspaceNotFound(name)
            }
            space = match
        } else if spaces.count == 1, let onlySpace = spaces.first {
            space = onlySpace
        } else {
            throw CLIError.invalidArguments("Specify --workspace when creating a terminal.")
        }

        let directory = URL(fileURLWithPath: targetPath).standardizedFileURL.resolvingSymlinksInPath().path
        let reference = HostPrivateReference(rawValue: "local-repository:\(directory)")
        let resources = try await client.resources(spaceID: space.id)
        let resourceID: ResourceID
        if let existing = resources.first(where: { $0.kind == .repository && $0.details == .hostPrivate(reference) }) {
            resourceID = existing.id
        } else {
            resourceID = try await client.importLocalRepository(spaceID: space.id, path: directory)
        }
        let contexts = try await client.executionContexts(spaceID: space.id, resourceID: resourceID)
        let executionContextID: ExecutionContextID
        if let existing = contexts.first(where: { $0.kind == .repositoryCheckout }) {
            executionContextID = existing.id
        } else {
            executionContextID = try await client.createRepositoryCheckoutContext(spaceID: space.id, resourceID: resourceID)
        }
        let terminal = try await client.createTerminalSession(
            spaceID: space.id,
            executionContextID: executionContextID,
            title: parsed.options["name"],
            initialCommand: parsed.options["command"]
        )
        let style = OutputStyle(useColor: shouldUseColor(flags: parsed.flags))
        if parsed.flags.contains("attach") {
            print(style.success("Created terminal for \(space.name)"))
            try tmuxAttach(sessionName: terminal.tmuxSessionName)
        } else {
            print(style.success("Created terminal: \(terminal.title ?? directory)"))
            print(style.label("Session: \(terminal.tmuxSessionName)"))
            print("Use \(style.header("aizen sessions --workspace \(space.name)")) to list Host-owned terminals.")
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
        let appURL = findAizenAppBundle()
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

    static func isCrossProjectRepository(_ repository: Repository) -> Bool {
        repository.isCrossProject || repository.note == CLIRepositoryManager.crossProjectRepositoryMarker
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
            if isCrossProjectRepository(repo) {
                return false
            }

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
           let repository = worktree.repository,
           !isCrossProjectRepository(repository) {
            return repository
        }

        let repoRequest: NSFetchRequest<Repository> = Repository.fetchRequest()
        repoRequest.predicate = NSPredicate(format: "path == %@", normalized)
        repoRequest.fetchLimit = 1
        if let repo = try? context.fetch(repoRequest).first,
           !isCrossProjectRepository(repo) {
            return repo
        }

        let allRequest: NSFetchRequest<Repository> = Repository.fetchRequest()
        guard let allRepos = try? context.fetch(allRequest) else {
            return nil
        }

        var bestMatch: Repository?
        var bestLength = 0
        for repo in allRepos {
            if isCrossProjectRepository(repo) {
                continue
            }

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
            if isCrossProjectRepository(repo) { continue }
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

    struct ResourceOutput: Encodable {
        let id: String
        let kind: String
        let title: String
        let space: String
    }

    struct ResourceListPayload: Encodable {
        let filters: RepositoryFilters
        let resources: [ResourceOutput]
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

    static func v2Workspaces(filters: WorkspaceFilters) async throws -> [Space] {
        let all = try await V2CLIClient().spaces().sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        let include = Set(filters.includeWorkspaces.map { $0.lowercased() })
        let exclude = Set(filters.excludeWorkspaces.map { $0.lowercased() })

        for name in filters.includeWorkspaces + filters.excludeWorkspaces {
            guard all.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                throw CLIError.workspaceNotFound(name)
            }
        }

        let nameContains = filters.nameContains?.lowercased()
        return all.filter { space in
            let name = space.name.lowercased()
            return (include.isEmpty || include.contains(name)) &&
                !exclude.contains(name) &&
                (nameContains.map { name.contains($0) } ?? true)
        }
    }

    static func v2Resources(filters: RepositoryFilters) async throws -> [Resource] {
        let spaces = try await v2Workspaces(filters: WorkspaceFilters(
            includeWorkspaces: filters.includeWorkspaces,
            excludeWorkspaces: filters.excludeWorkspaces,
            nameContains: nil
        ))
        let namesByID = Dictionary(uniqueKeysWithValues: spaces.map { ($0.id, $0.name) })
        let nameContains = filters.nameContains?.lowercased()
        return try await V2CLIClient().resources().filter { resource in
            guard namesByID[resource.spaceID] != nil else { return false }
            return nameContains.map { resource.title.lowercased().contains($0) } ?? true
        }
    }

    struct StatusPayload: Encodable {
        let spaces: Int
        let resources: Int
        let executionContexts: Int
        let conversations: Int
        let runs: Int
        let filters: WorkspaceFilters
    }

    struct TerminalSessionOutput: Encodable {
        let id: String
        let space: String
        let title: String
        let tmuxSession: String
        let paneID: String
    }

    struct TerminalSessionListPayload: Encodable {
        let sessions: [TerminalSessionOutput]
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

    static func printResourceTable(_ resources: [Resource], style: OutputStyle) {
        let spaces = Dictionary(uniqueKeysWithValues: resources.map { ($0.spaceID, $0.spaceID.description) })
        let rows = resources.map { resource in
            [resource.title, resource.kind.rawValue, spaces[resource.spaceID] ?? "-", resource.id.description]
        }
        printTable(headers: ["Resource", "Kind", "Space ID", "ID"], rows: rows, style: style)
    }

    static func printWorkspaceTable(_ workspaces: [Workspace], style: OutputStyle) {
        let headers = ["Workspace", "Color", "Repositories", "Order"]
        var rows: [[String]] = []
        for workspace in workspaces {
            let name = workspace.name ?? ""
            let color = workspace.colorHex ?? "-"
            let repoCount = String(((workspace.repositories as? Set<Repository>)?.filter { !isCrossProjectRepository($0) }.count) ?? 0)
            let order = String(workspace.order)
            rows.append([name, color, repoCount, order])
        }
        printTable(headers: headers, rows: rows, style: style)
    }

    static func printWorkspaceTable(_ spaces: [Space], style: OutputStyle) {
        let headers = ["Workspace", "Color", "Repositories", "Order"]
        let rows = spaces.enumerated().map { index, space in
            [space.name, space.icon ?? "-", "0", String(index)]
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

    static func resourceOutput(_ resource: Resource) -> ResourceOutput {
        ResourceOutput(
            id: resource.id.description,
            kind: resource.kind.rawValue,
            title: resource.title,
            space: resource.spaceID.description
        )
    }

    static func workspaceOutput(_ workspace: Workspace) -> WorkspaceOutput {
        WorkspaceOutput(
            name: workspace.name ?? "",
            color: workspace.colorHex,
            repositories: ((workspace.repositories as? Set<Repository>)?.filter { !isCrossProjectRepository($0) }.count) ?? 0,
            order: Int(workspace.order)
        )
    }

    static func workspaceOutput(_ space: (offset: Int, element: Space)) -> WorkspaceOutput {
        WorkspaceOutput(name: space.element.name, color: space.element.icon, repositories: 0, order: space.offset)
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
  aizen                           Open Aizen
  aizen open [path]               Open path in Aizen (adds to workspace if not tracked)
  aizen add [path|url]            Add repository to workspace
  aizen remove <path>             Remove repository from tracking
  aizen list [space]              List v2 resources
  aizen workspace <command>       Manage workspaces
  aizen sync [path]               Rescan worktrees
  aizen status                    Show overview
  aizen terminal [path]           Create persistent terminal session
  aizen attach [project]          Attach to tmux terminal session
  aizen sessions                  List active terminal sessions

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

Lists v2 Resources without exposing Host-owned paths.

Options:
  -w, --workspace <name>         Filter by workspace (comma-separated)
  --exclude-workspace <name>     Exclude workspace(s) (comma-separated)
  --name <text>                  Filter by resource title
  --path <text>                  Unavailable for v2 Resources
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
  aizen conversation show <session-id>
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

Shows a v2 Host overview of Spaces, Resources, Contexts, Conversations, and Runs.

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
  aizen open .

Opens Aizen and navigates to the repository at the given path.

If the path is not tracked in any workspace, you will be prompted to select
a workspace to add it to. Use '.' to open the current directory.
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

    static func attachHelpText() -> String {
        return """
Usage:
  aizen attach <terminal-title-or-id>            Attach to a Host-owned terminal
  aizen attach <terminal-title-or-id> --workspace <space>
  aizen attach --workspace <space>               Attach when the Space has one terminal

Options:
  -w, --workspace <name>    Filter Host-owned terminals by Space
  --no-color                Disable colored output

Attach to an active Host-owned tmux terminal session from Aizen.
Use a terminal title or unique session ID prefix when more than one matches.
"""
    }


    static func sessionsHelpText() -> String {
        return """
Usage:
  aizen sessions [--workspace <name>] [--cross-project] [--json]

Options:
  -w, --workspace <name>    Filter sessions by workspace
  --cross-project           Show only cross-project sessions
  --json                    Output JSON
  --no-color                Disable colored output

List all active terminal sessions with their tmux panes.
"""
    }


    static func terminalHelpText() -> String {
        return """
Usage:
  aizen terminal [path]                                Create detached terminal session
  aizen terminal . --attach                            Create and attach
  aizen terminal . -c "npm run dev"                   Run command in session
  aizen terminal . --name "Dev Server"                Custom tab name

Options:
  -a, --attach              Attach to session after creating
  -c, --command <cmd>       Run command in the terminal
  --name <name>             Custom name for the terminal tab
  -w, --workspace <name>    Space for the Host-owned repository terminal
  --no-color                Disable colored output

Create a new Host-owned terminal session that persists via tmux.
When a repository is not tracked yet, it is imported into the selected Space.
"""
    }

}
