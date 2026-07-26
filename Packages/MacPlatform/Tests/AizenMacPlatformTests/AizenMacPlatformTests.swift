import ACP
import AizenCore
import AizenHost
@testable import AizenMacPlatform
import AizenSecurity
import AizenStorage
import AizenTransport
import AizenWire
import Foundation
import Security
import Testing

@Test func hostMachServiceConfigurationBuildsTheTeamRequirement() throws {
    let configuration = try HostMachServiceConfiguration(
        machServiceName: "win.aizen.host",
        teamIdentifier: "QW4U57CXJX"
    )

    #expect(configuration.peerCodeSigningRequirement == "anchor apple generic and certificate leaf[subject.OU] = \"QW4U57CXJX\"")
    #expect(throws: HostMachServiceConfigurationError.invalidTeamIdentifier) {
        _ = try HostMachServiceConfiguration(machServiceName: "win.aizen.host", teamIdentifier: "QW4U57CXJX\"")
    }
}

@Test func developmentHostConfigurationAllowsOnlyBundledDebugProducts() throws {
    let configuration = try HostMachServiceConfiguration(
        machServiceName: "win.aizen.host",
        teamIdentifier: "QW4U57CXJX",
        allowsDevelopmentClients: true
    )

    #expect(configuration.peerCodeSigningRequirement == "identifier \"Aizen\" or identifier \"aizen-cli\"")
}

@Test func machWireServiceExportsStableHostErrorCodes() {
    #expect(hostErrorPayload(for: HostProtocolError.unknownResource(ResourceID())).code == HostErrorCode.unknownResource.rawValue)
    #expect(hostErrorPayload(for: HostProtocolError.runtimeUnavailable).code == HostErrorCode.unavailable.rawValue)
    #expect(hostErrorPayload(for: NSError(domain: "test", code: 1)).code == HostErrorCode.commandFailed.rawValue)
}

@Test func machResponseContinuationKeepsTheFirstReplyAfterTimeoutOrLateXPCResponse() async throws {
    let response: Data = try await withCheckedThrowingContinuation { continuation in
        let reply = MachResponseContinuation(continuation: continuation)
        reply.resume(returning: Data("first".utf8))
        reply.resume(throwing: MachWireTransportError.timeout)
    }

    #expect(String(decoding: response, as: UTF8.self) == "first")
}

@Test func machEventHubFinishesInterruptedSubscriptionsBeforeAClientResubscribes() async {
    let hub = MachRunEventHub()
    let stream = await hub.stream()
    let nextEvent = Task {
        var iterator = stream.makeAsyncIterator()
        return await iterator.next()
    }

    await hub.finish()
    #expect(await nextEvent.value == nil)
}

@Test func localHostRuntimeFailsInterruptedOperationsBeforeServingClients() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storageURL = root.appendingPathComponent("storage-v2.json")
    let storage = StorageRepository(url: storageURL)
    let space = Space(name: "Recovery")
    let operation = Operation(spaceID: space.id, lifecycle: .running, progress: 0.5)
    _ = try await storage.transact { snapshot in
        snapshot.spaces.append(space)
        snapshot.operations.append(operation)
    }

    let runtime = LocalHostRuntime(storageURL: storageURL)
    #expect(try await runtime.recoverInterruptedOperations() == 1)
    let recovered = try #require(try await storage.load().operations.first)
    #expect(recovered.lifecycle == .failed)
    #expect(recovered.failureDescription == "Aizen Host restarted before this operation completed.")
}

@Test func hostDiagnosticsAreDerivedFromHostRuntimeState() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storageURL = root.appendingPathComponent("storage-v2.json")
    let storage = StorageRepository(url: storageURL)
    let space = Space(name: "Diagnostics")
    let session = Session(spaceID: space.id, kind: .conversation, title: "Diagnostics")
    _ = try await storage.transact { snapshot in
        snapshot.spaces.append(space)
        snapshot.sessions.append(session)
        snapshot.runs.append(.init(spaceID: space.id, sessionID: session.id, lifecycle: .running))
        snapshot.operations.append(.init(spaceID: space.id, lifecycle: .running, progress: 0.5))
    }

    let diagnostics = await LocalHostRuntime(storageURL: storageURL).diagnostics()
    #expect(diagnostics.storageState == .ready)
    #expect(diagnostics.migrationState == .idle)
    #expect(diagnostics.activeRunCount == 1)
    #expect(diagnostics.activeOperationCount == 1)
    #expect(diagnostics.lastStartupError == nil)
}

@Test func connectionRegistryTracksOnlyLivePeers() {
    let registry = HostConnectionRegistry()
    let first = registry.connect()
    let second = registry.connect()
    #expect(registry.count == 2)
    registry.disconnect(first)
    registry.disconnect(second)
    #expect(registry.count == 0)
}

@Test func startupStatusRetainsOnlyTheLastReportedStartupError() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storageURL = root.appendingPathComponent("storage-v2.json")

    try HostStartupStatusStore.recordFailure(NSError(domain: "Host", code: 1, userInfo: [NSLocalizedDescriptionKey: "Listener unavailable"]), storageURL: storageURL)
    try HostStartupStatusStore.recordFailure(NSError(domain: "Host", code: 2, userInfo: [NSLocalizedDescriptionKey: "Listener still unavailable"]), storageURL: storageURL)
    #expect(HostStartupStatusStore.lastError(storageURL: storageURL) == "Listener still unavailable")
    #expect(HostStartupStatusStore.consecutiveFailureCount(storageURL: storageURL) == 2)
    try HostStartupStatusStore.clearFailure(storageURL: storageURL)
    #expect(HostStartupStatusStore.lastError(storageURL: storageURL) == nil)
    #expect(HostStartupStatusStore.consecutiveFailureCount(storageURL: storageURL) == 0)
}

@Test func gitRepositoryStatusReaderParsesRealBoundedPorcelainStatus() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try runGit(["init", "--initial-branch=main", root.path])
    try Data("staged".utf8).write(to: root.appendingPathComponent("staged.swift"))
    try runGit(["-C", root.path, "add", "staged.swift"])
    try Data("modified".utf8).write(to: root.appendingPathComponent("modified.swift"))

    let reader = GitRepositoryStatusReader()
    let first = try await reader.status(at: root, maximumEntries: 1)
    #expect(first.entries.count == 1)
    #expect(first.truncated)
    #expect(first.repositoryRevision == "unborn:main")
    #expect(first.indexRevision.count == 64)

    let full = try await reader.status(at: root, maximumEntries: 10)
    #expect(full.entries.contains(.init(path: "staged.swift", indexStatus: "A", worktreeStatus: ".")))
    #expect(full.entries.contains(.init(path: "modified.swift", indexStatus: "?", worktreeStatus: "?")))
    #expect(!full.truncated)
}

@Test func gitRepositoryStatusReaderReturnsBoundedRealDiff() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try runGit(["init", "--initial-branch=main", root.path])
    try runGit(["-C", root.path, "config", "user.email", "aizen@example.test"])
    try runGit(["-C", root.path, "config", "user.name", "Aizen Test"])
    let file = root.appendingPathComponent("README.md")
    try Data("before\n".utf8).write(to: file)
    try runGit(["-C", root.path, "add", "README.md"])
    try runGit(["-C", root.path, "commit", "-m", "seed"])
    try Data("after\n".utf8).write(to: file)

    let reader = GitRepositoryStatusReader()
    let diff = try await reader.diff(at: root, relativePath: "README.md", maximumBytes: 4_096)
    let text = String(decoding: diff.unifiedDiff, as: UTF8.self)
    #expect(text.contains("-before"))
    #expect(text.contains("+after"))
    #expect(diff.repositoryRevision.count == 40)
    #expect(diff.indexRevision.count == 64)

    let bounded = try await reader.diff(at: root, relativePath: "README.md", maximumBytes: 20)
    #expect(bounded.unifiedDiff.count == 20)
    #expect(bounded.truncated)
}

@Test func gitRepositoryStatusReaderReturnsBoundedRealHistory() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try runGit(["init", "--initial-branch=main", root.path])
    try runGit(["-C", root.path, "config", "user.email", "aizen@example.test"])
    try runGit(["-C", root.path, "config", "user.name", "Aizen Test"])
    let file = root.appendingPathComponent("README.md")
    for value in ["one", "two"] {
        try Data("\(value)\n".utf8).write(to: file)
        try runGit(["-C", root.path, "add", "README.md"])
        try runGit(["-C", root.path, "commit", "-m", value])
    }

    let history = try await GitRepositoryStatusReader().history(at: root, maximumCommits: 1)
    #expect(history.branch == "main")
    #expect(!history.isDetached)
    #expect(history.commits.map(\.subject) == ["two"])
    #expect(history.truncated)
    #expect(history.repositoryRevision.count == 40)
    #expect(history.indexRevision.count == 64)
}

@Test func gitRepositoryStatusReaderUpdatesTheIndexOnlyAtTheExpectedRevision() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try runGit(["init", "--initial-branch=main", root.path])
    try runGit(["-C", root.path, "config", "user.email", "aizen@example.test"])
    try runGit(["-C", root.path, "config", "user.name", "Aizen Test"])
    let file = root.appendingPathComponent("README.md")
    try Data("before\n".utf8).write(to: file)
    try runGit(["-C", root.path, "add", "README.md"])
    try runGit(["-C", root.path, "commit", "-m", "seed"])
    try Data("after\n".utf8).write(to: file)

    let reader = GitRepositoryStatusReader()
    let beforeStage = try await reader.status(at: root, maximumEntries: 10)
    let stagedRevision = try await reader.updateIndex(
        at: root,
        relativePaths: ["README.md"],
        expectedIndexRevision: beforeStage.indexRevision,
        stage: true
    )
    #expect(stagedRevision != beforeStage.indexRevision)
    #expect(try gitOutput(["-C", root.path, "diff", "--cached", "--name-only"]) == "README.md")

    await #expect(throws: GitRepositoryStatusReader.Error.indexRevisionConflict) {
        _ = try await reader.updateIndex(
            at: root,
            relativePaths: ["README.md"],
            expectedIndexRevision: beforeStage.indexRevision,
            stage: false
        )
    }

    let afterStage = try await reader.status(at: root, maximumEntries: 10)
    let unstagedRevision = try await reader.updateIndex(
        at: root,
        relativePaths: ["README.md"],
        expectedIndexRevision: afterStage.indexRevision,
        stage: false
    )
    #expect(unstagedRevision != afterStage.indexRevision)
    #expect(try gitOutput(["-C", root.path, "diff", "--cached", "--name-only"]).isEmpty)
}

@Test func gitRepositoryStatusReaderReturnsBoundedLocalBranches() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try runGit(["init", "--initial-branch=main", root.path])
    try runGit(["-C", root.path, "config", "user.email", "aizen@example.test"])
    try runGit(["-C", root.path, "config", "user.name", "Aizen Test"])
    try Data("seed\n".utf8).write(to: root.appendingPathComponent("README.md"))
    try runGit(["-C", root.path, "add", "README.md"])
    try runGit(["-C", root.path, "commit", "-m", "seed"])
    try runGit(["-C", root.path, "branch", "feature/test"])

    let branches = try await GitRepositoryStatusReader().branches(at: root, maximumBranches: 1)
    #expect(branches.branches.count == 1)
    #expect(branches.branches.first?.name == "feature/test")
    #expect(!branches.branches[0].isCurrent)
    #expect(branches.truncated)
    #expect(branches.repositoryRevision.count == 40)
    #expect(branches.indexRevision.count == 64)
}

@Test func gitRepositoryStatusReaderCommitsAndAmendsAtExpectedRevisions() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try runGit(["init", "--initial-branch=main", root.path])
    try runGit(["-C", root.path, "config", "user.email", "aizen@example.test"])
    try runGit(["-C", root.path, "config", "user.name", "Aizen Test"])
    let file = root.appendingPathComponent("README.md")
    try Data("seed\n".utf8).write(to: file)
    try runGit(["-C", root.path, "add", "README.md"])

    let reader = GitRepositoryStatusReader()
    let initial = try await reader.status(at: root, maximumEntries: 10)
    let committed = try await reader.commit(at: root, message: "seed", expectedRepositoryRevision: initial.repositoryRevision, expectedIndexRevision: initial.indexRevision, amend: false)
    #expect(committed.repositoryRevision.count == 40)
    #expect(try gitOutput(["-C", root.path, "log", "-1", "--format=%s"]) == "seed")

    await #expect(throws: GitRepositoryStatusReader.Error.repositoryRevisionConflict) {
        _ = try await reader.commit(at: root, message: "stale", expectedRepositoryRevision: initial.repositoryRevision, expectedIndexRevision: committed.indexRevision, amend: false)
    }

    try Data("amended\n".utf8).write(to: file)
    try runGit(["-C", root.path, "add", "README.md"])
    let beforeAmend = try await reader.status(at: root, maximumEntries: 10)
    let amended = try await reader.commit(at: root, message: "amended", expectedRepositoryRevision: beforeAmend.repositoryRevision, expectedIndexRevision: beforeAmend.indexRevision, amend: true)
    #expect(amended.repositoryRevision != beforeAmend.repositoryRevision)
    #expect(try gitOutput(["-C", root.path, "log", "-1", "--format=%s"]) == "amended")
}

@Test func gitRepositoryStatusReaderCreatesAndSwitchesBranchesAtExpectedRevisions() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try runGit(["init", "--initial-branch=main", root.path])
    try runGit(["-C", root.path, "config", "user.email", "aizen@example.test"])
    try runGit(["-C", root.path, "config", "user.name", "Aizen Test"])
    try Data("seed\n".utf8).write(to: root.appendingPathComponent("README.md"))
    try runGit(["-C", root.path, "add", "README.md"])
    try runGit(["-C", root.path, "commit", "-m", "seed"])

    let reader = GitRepositoryStatusReader()
    let main = try await reader.status(at: root, maximumEntries: 10)
    _ = try await reader.updateBranch(at: root, branchName: "feature/reignition", expectedRepositoryRevision: main.repositoryRevision, expectedIndexRevision: main.indexRevision, create: true)
    #expect(try gitOutput(["-C", root.path, "branch", "--show-current"]) == "feature/reignition")

    let feature = try await reader.status(at: root, maximumEntries: 10)
    _ = try await reader.updateBranch(at: root, branchName: "main", expectedRepositoryRevision: feature.repositoryRevision, expectedIndexRevision: feature.indexRevision, create: false)
    #expect(try gitOutput(["-C", root.path, "branch", "--show-current"]) == "main")

    await #expect(throws: GitRepositoryStatusReader.Error.repositoryRevisionConflict) {
        _ = try await reader.updateBranch(at: root, branchName: "feature/reignition", expectedRepositoryRevision: "stale", expectedIndexRevision: feature.indexRevision, create: false)
    }
}

@Test func gitRepositoryStatusReaderFetchesFromTheFixedOriginAtExpectedRevisions() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let remote = root.appendingPathComponent("remote.git", isDirectory: true)
    let repository = root.appendingPathComponent("repository", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try runGit(["init", "--bare", remote.path])
    try runGit(["init", "--initial-branch=main", repository.path])
    try runGit(["-C", repository.path, "config", "user.email", "aizen@example.test"])
    try runGit(["-C", repository.path, "config", "user.name", "Aizen Test"])
    try Data("seed\n".utf8).write(to: repository.appendingPathComponent("README.md"))
    try runGit(["-C", repository.path, "add", "README.md"])
    try runGit(["-C", repository.path, "commit", "-m", "seed"])
    try runGit(["-C", repository.path, "remote", "add", "origin", remote.path])
    try runGit(["-C", repository.path, "push", "-u", "origin", "main"])

    let reader = GitRepositoryStatusReader()
    let status = try await reader.status(at: repository, maximumEntries: 10)
    let fetched = try await reader.fetch(at: repository, expectedRepositoryRevision: status.repositoryRevision, expectedIndexRevision: status.indexRevision)
    #expect(fetched.repositoryRevision == status.repositoryRevision)
    #expect(fetched.indexRevision == status.indexRevision)
}

@Test func gitRepositoryStatusReaderFastForwardsFromOriginAtExpectedRevisions() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let remote = root.appendingPathComponent("remote.git", isDirectory: true)
    let repository = root.appendingPathComponent("repository", isDirectory: true)
    let writer = root.appendingPathComponent("writer", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try runGit(["init", "--bare", remote.path])
    try runGit(["clone", remote.path, repository.path])
    try runGit(["-C", repository.path, "config", "user.email", "aizen@example.test"])
    try runGit(["-C", repository.path, "config", "user.name", "Aizen Test"])
    try Data("seed\n".utf8).write(to: repository.appendingPathComponent("README.md"))
    try runGit(["-C", repository.path, "add", "README.md"])
    try runGit(["-C", repository.path, "commit", "-m", "seed"])
    try runGit(["-C", repository.path, "push", "-u", "origin", "HEAD:main"])
    try runGit(["--git-dir", remote.path, "symbolic-ref", "HEAD", "refs/heads/main"])
    try runGit(["clone", remote.path, writer.path])
    try runGit(["-C", writer.path, "config", "user.email", "aizen@example.test"])
    try runGit(["-C", writer.path, "config", "user.name", "Aizen Test"])
    try Data("remote\n".utf8).write(to: writer.appendingPathComponent("REMOTE.md"))
    try runGit(["-C", writer.path, "add", "REMOTE.md"])
    try runGit(["-C", writer.path, "commit", "-m", "remote"])
    try runGit(["-C", writer.path, "push"])

    let reader = GitRepositoryStatusReader()
    let before = try await reader.status(at: repository, maximumEntries: 10)
    let pulled = try await reader.pull(at: repository, expectedRepositoryRevision: before.repositoryRevision, expectedIndexRevision: before.indexRevision)
    #expect(pulled.repositoryRevision != before.repositoryRevision)
    #expect(FileManager.default.fileExists(atPath: repository.appendingPathComponent("REMOTE.md").path))
}

@Test func hostIdentityIsStableAcrossHostRestarts() async throws {
    let persistence = MemoryHostIdentityPersistence()
    let first = try await HostIdentityStore(persistence: persistence).loadOrCreate(displayName: "Mac")
    let second = try await HostIdentityStore(persistence: persistence).loadOrCreate(displayName: "Renamed Mac")

    #expect(first.hostID == second.hostID)
    #expect(first.cryptographicIdentity.fingerprint == second.cryptographicIdentity.fingerprint)
    #expect(second.displayName == "Renamed Mac")
}

@Test func hostIdentityCredentialsKeepTheKeychainIdentityInMemoryOnly() async throws {
    let persistence = MemoryHostIdentityPersistence()
    let credentials = try await HostIdentityStore(persistence: persistence).loadOrCreateCredentials(displayName: "Mac")
    let message = Data("aizen-host".utf8)
    #expect(credentials.publicIdentity.cryptographicIdentity.verifies(signature: credentials.localIdentity.sign(message), message: message))
}

@Test func bonjourMetadataPublishesOnlyProtocolAndIdentityHints() throws {
    let identity = LocalCryptographicIdentity()
    let host = HostPublicIdentity(hostID: HostID(), displayName: "Wiedy's Mac", cryptographicIdentity: identity.publicIdentity())
    let metadata = HostBonjourMetadata(host: host, minimumProtocolGeneration: 1, maximumProtocolGeneration: 2)
    let values = metadata.txtRecord.mapValues { String(decoding: $0, as: UTF8.self) }

    #expect(Set(values.keys) == ["pr", "h", "fp", "pair"])
    #expect(values["pr"] == "1-2")
    #expect(values["fp"] == host.cryptographicIdentity.fingerprint.prefix)
    #expect(values["pair"] == "1")
    #expect(values.values.joined().contains("Wiedy") == false)
}

@Test func pairedTLSOptionsKeepTheHostReachableBeforeFirstPairing() throws {
    _ = try PairedTLSOptions.server()
    _ = PairedTLSOptions.client()
}

@Test func bootstrapTLSCertificateIsAValidSelfSignedTrustAnchor() throws {
    let data = try BootstrapTLSIdentity.makeCertificateData()
    let certificate = try #require(SecCertificateCreateWithData(nil, data as CFData))
    var trust: SecTrust?
    #expect(SecTrustCreateWithCertificates(certificate, SecPolicyCreateSSL(true, "127.0.0.1" as CFString), &trust) == errSecSuccess)
    let evaluatedTrust = try #require(trust)
    #expect(SecTrustSetAnchorCertificates(evaluatedTrust, [certificate] as CFArray) == errSecSuccess)
    #expect(SecTrustSetAnchorCertificatesOnly(evaluatedTrust, true) == errSecSuccess)
    var error: CFError?
    guard SecTrustEvaluateWithError(evaluatedTrust, &error) else {
        throw error ?? NSError(domain: "AizenMacPlatformTests", code: 1)
    }
}

@Test @MainActor func pairedWebSocketConnectorAuthenticatesAgainstTheLiveHostListener() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let hostIdentity = LocalCryptographicIdentity()
    let host = HostPublicIdentity(hostID: HostID(), displayName: "Mac", cryptographicIdentity: hostIdentity.publicIdentity())
    let deviceIdentity = LocalCryptographicIdentity()
    let device = DevicePublicIdentity(deviceID: DeviceID(), displayName: "Phone", platform: "iOS", cryptographicIdentity: deviceIdentity.publicIdentity())
    try await storage.saveDeviceAuthorization(.init(device: device, grants: [.init(capability: .hostRead)]))
    let listener = HostLANWebSocketListener(
        host: host,
        hostIdentity: hostIdentity,
        storage: storage,
        endpoint: LocalHost(storage: storage),
        pairing: PairingRequestRegistry(hostID: host.hostID, approval: PairingApprovalService(storage: storage)),
        terminalControl: TerminalControlLeaseRegistry()
    )
    try await listener.start()
    defer { listener.stop() }
    let port = try await listenerPort(listener)
    let route = try TransportRouteConfiguration(
        kind: .lan,
        endpoint: URL(string: "wss://localhost:\(port)")!,
        expectedHostIdentity: host.cryptographicIdentity.fingerprint.description
    )
    let connection = try await RemoteWebSocketRouteConnector(host: host, device: device, deviceIdentity: deviceIdentity).connect(route: route)
    let response = try await connection.transport.send(.init(
        messageID: "live-websocket",
        connectionSequence: 1,
        kind: .hello,
        channel: .control,
        payload: try .init(HelloPayload(minimumProtocolGeneration: 1, maximumProtocolGeneration: 1, productVersion: "2.0.0"))
    ))
    #expect(response.kind == .capabilities)
}

@MainActor
private func listenerPort(_ listener: HostLANWebSocketListener) async throws -> UInt16 {
    for _ in 0..<100 {
        if let port = listener.port { return port }
        try await Task.sleep(for: .milliseconds(10))
    }
    throw RemoteWebSocketTransportError.connectionFailed("Listener did not publish a port.")
}

@Test func lanWebSocketProcessorAuthenticatesAndSealsRemoteRequests() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "LAN")
    _ = try await storage.transact { $0.spaces.append(space) }
    let hostIdentity = LocalCryptographicIdentity()
    let host = HostPublicIdentity(hostID: HostID(), displayName: "Mac", cryptographicIdentity: hostIdentity.publicIdentity())
    let deviceIdentity = LocalCryptographicIdentity()
    let device = DevicePublicIdentity(deviceID: DeviceID(), displayName: "Phone", platform: "iOS", cryptographicIdentity: deviceIdentity.publicIdentity())
    try await storage.saveDeviceAuthorization(.init(device: device, grants: [.init(capability: .hostRead)]))
    let source = RemoteRequestSource("192.168.1.20")
    let rateLimiter = RemoteRequestRateLimiter()
    let processor = HostLANWebSocketProcessor(
        host: host,
        hostIdentity: hostIdentity,
        authenticator: RemoteSessionAuthenticator(host: host, hostIdentity: hostIdentity, storage: storage, rateLimiter: rateLimiter),
        endpoint: LocalHost(storage: storage),
        storage: storage,
        authorization: DeviceAuthorizationGate(storage: storage),
        rateLimiter: rateLimiter,
        pairing: PairingRequestRegistry(hostID: host.hostID, approval: PairingApprovalService(storage: storage)),
        terminalControl: TerminalControlLeaseRegistry(),
        source: source
    )
    let connectionID = UUID()
    let clientEphemeral = ConnectionEphemeralKey()
    let start = AuthenticationStartPayload(
        hostID: host.hostID,
        deviceID: device.deviceID,
        connectionID: connectionID,
        clientNonce: Data(repeating: 1, count: 32),
        deviceSigningPublicKey: device.cryptographicIdentity.signingPublicKey,
        deviceKeyAgreementPublicKey: device.cryptographicIdentity.keyAgreementPublicKey,
        clientEphemeralPublicKey: clientEphemeral.publicKey,
        route: "lan"
    )
    let startEnvelope = try ProtocolEnvelope(
        messageID: "start",
        connectionID: connectionID.uuidString,
        connectionSequence: 1,
        kind: .authentication,
        channel: .control,
        payload: .init(start)
    )
    let challengeEnvelope = try ProtocolEnvelope(serializedData: try await processor.receive(startEnvelope.serializedData()))
    let challenge = try AuthenticationChallengePayload(protobufBytes: challengeEnvelope.payload.protobufBytes)
    let binding = try ConnectionAuthenticationBinding(
        protocolGeneration: challengeEnvelope.protocolGeneration,
        hostID: challenge.hostID,
        deviceID: challenge.deviceID,
        connectionID: challenge.connectionID,
        clientNonce: challenge.clientNonce,
        serverNonce: challenge.serverNonce,
        clientEphemeralPublicKey: clientEphemeral.publicKey,
        serverEphemeralPublicKey: challenge.serverEphemeralPublicKey,
        route: .lan
    )
    let proof = ConnectionAuthenticator.makeProof(participant: .device, identity: deviceIdentity, binding: binding)
    let proofEnvelope = ProtocolEnvelope(
        messageID: "proof",
        connectionID: connectionID.uuidString,
        connectionSequence: 2,
        kind: .authentication,
        channel: .control,
        payload: try .init(AuthenticationProofPayload(connectionID: connectionID, deviceSignature: proof.signature))
    )
    let deviceKeys = try ConnectionAuthenticator.deriveKeys(participant: .device, ephemeralKey: clientEphemeral, peerEphemeralPublicKey: challenge.serverEphemeralPublicKey, binding: binding)
    let deviceChannel = AuthenticatedWireChannel(keys: deviceKeys, binding: binding)
    let capabilities = try await deviceChannel.open(try await processor.receive(proofEnvelope.serializedData()))
    #expect(capabilities.kind == .capabilities)

    let request = ProtocolEnvelope(messageID: "spaces", connectionSequence: 3, kind: .query, channel: .state, payload: try .init(ListSpacesQueryPayload()))
    let response = try await deviceChannel.open(try await processor.receive(try await deviceChannel.seal(request)))
    #expect(try ListSpacesResponsePayload(protobufBytes: response.payload.protobufBytes).spaces.map(\.name) == ["LAN"])
}

@Test func lanWebSocketProcessorQueuesFirstDevicePairingOnlyAfterHostProof() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let hostIdentity = LocalCryptographicIdentity()
    let host = HostPublicIdentity(hostID: HostID(), displayName: "Mac", cryptographicIdentity: hostIdentity.publicIdentity())
    let deviceIdentity = LocalCryptographicIdentity()
    let device = DevicePublicIdentity(deviceID: DeviceID(), displayName: "Phone", platform: "iOS", cryptographicIdentity: deviceIdentity.publicIdentity())
    let invitation = try PairingInvitation(secret: Data(repeating: 9, count: 32), host: host, endpointHints: [], expiresAt: Date().addingTimeInterval(60))
    let approval = PairingApprovalService(storage: storage)
    try await approval.issue(invitation)
    let pairing = PairingRequestRegistry(hostID: host.hostID, approval: approval)
    let source = RemoteRequestSource("192.168.1.20")
    let rateLimiter = RemoteRequestRateLimiter()
    let processor = HostLANWebSocketProcessor(
        host: host,
        hostIdentity: hostIdentity,
        authenticator: RemoteSessionAuthenticator(host: host, hostIdentity: hostIdentity, storage: storage, rateLimiter: rateLimiter),
        endpoint: LocalHost(storage: storage),
        storage: storage,
        authorization: DeviceAuthorizationGate(storage: storage),
        rateLimiter: rateLimiter,
        pairing: pairing,
        terminalControl: TerminalControlLeaseRegistry(),
        source: source
    )
    let connectionID = UUID()
    let clientEphemeral = ConnectionEphemeralKey()
    let start = AuthenticationStartPayload(
        hostID: host.hostID,
        deviceID: device.deviceID,
        connectionID: connectionID,
        clientNonce: Data(repeating: 3, count: 32),
        deviceSigningPublicKey: device.cryptographicIdentity.signingPublicKey,
        deviceKeyAgreementPublicKey: device.cryptographicIdentity.keyAgreementPublicKey,
        clientEphemeralPublicKey: clientEphemeral.publicKey,
        route: "lan"
    )
    let challengeEnvelope = try ProtocolEnvelope(serializedData: try await processor.receive(ProtocolEnvelope(messageID: "start", connectionID: connectionID.uuidString, connectionSequence: 1, kind: .authentication, channel: .control, payload: .init(start)).serializedData()))
    let challenge = try AuthenticationChallengePayload(protobufBytes: challengeEnvelope.payload.protobufBytes)
    let binding = try ConnectionAuthenticationBinding(
        protocolGeneration: challengeEnvelope.protocolGeneration,
        hostID: challenge.hostID,
        deviceID: challenge.deviceID,
        connectionID: challenge.connectionID,
        clientNonce: challenge.clientNonce,
        serverNonce: challenge.serverNonce,
        clientEphemeralPublicKey: clientEphemeral.publicKey,
        serverEphemeralPublicKey: challenge.serverEphemeralPublicKey,
        route: .lan
    )
    try ConnectionAuthenticator.verify(.init(participant: .host, signature: challenge.hostSignature), expectedParticipant: .host, identity: host.cryptographicIdentity, binding: binding)
    let proof = ConnectionAuthenticator.makeProof(participant: .device, identity: deviceIdentity, binding: binding)
    let deviceKeys = try ConnectionAuthenticator.deriveKeys(participant: .device, ephemeralKey: clientEphemeral, peerEphemeralPublicKey: challenge.serverEphemeralPublicKey, binding: binding)
    let channel = AuthenticatedWireChannel(keys: deviceKeys, binding: binding)
    let capabilities = try await channel.open(try await processor.receive(ProtocolEnvelope(messageID: "proof", connectionID: connectionID.uuidString, connectionSequence: 2, kind: .authentication, channel: .control, payload: try .init(AuthenticationProofPayload(connectionID: connectionID, deviceSignature: proof.signature))).serializedData()))
    #expect(capabilities.kind == .capabilities)

    let request = PairingRequestPayload(tokenID: invitation.tokenID, pairingSecret: invitation.secret, hostID: host.hostID, deviceID: device.deviceID, deviceDisplayName: device.displayName, devicePlatform: device.platform, deviceSigningPublicKey: device.cryptographicIdentity.signingPublicKey, deviceKeyAgreementPublicKey: device.cryptographicIdentity.keyAgreementPublicKey, route: "lan")
    let pending = try await channel.open(try await processor.receive(try await channel.seal(ProtocolEnvelope(messageID: "pair", connectionID: connectionID.uuidString, connectionSequence: 3, kind: .command, channel: .control, payload: .init(request)))))
    #expect(try PairingPendingPayload(protobufBytes: pending.payload.protobufBytes).tokenID == invitation.tokenID)
    #expect(await pairing.pending().map(\.tokenID) == [invitation.tokenID])
    #expect(try await storage.deviceAuthorizations().isEmpty)
}

@Test func localHostRuntimeOwnsTheStorageBackedHost() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let runtime = LocalHostRuntime(storageURL: root.appendingPathComponent("storage-v2.json"))
    let transport = InProcessTransport(endpoint: runtime.host)
    let request = ProtocolEnvelope(
        messageID: "runtime-space",
        connectionSequence: 1,
        kind: .command,
        channel: .state,
        payload: try .init(CreateSpaceCommandPayload(name: "Runtime"))
    )

    let response = try await transport.send(request)

    #expect(UUID(uuidString: try CreateSpaceResultPayload(protobufBytes: response.payload.protobufBytes).spaceID) != nil)
}

@Test func gitLinkedWorktreeServiceCreatesARealLinkedCheckout() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source", isDirectory: true)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try git(["init", source.path])
    try git(["-C", source.path, "config", "user.email", "test@example.com"])
    try git(["-C", source.path, "config", "user.name", "Aizen Test"])
    try "seed".write(to: source.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
    try git(["-C", source.path, "add", "README.md"])
    try git(["-C", source.path, "commit", "-m", "seed"])
    let destination = root.appendingPathComponent("feature", isDirectory: true)

    try await GitLinkedWorktreeService().createLinkedWorktree(source: source, destination: destination, branch: "feature/test", createBranch: true, baseBranch: "HEAD")

    #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent(".git").path))
    #expect(try gitOutput(["-C", destination.path, "branch", "--show-current"]) == "feature/test")
}

@Test func independentContextServiceCreatesCloneAndGitlessCopy() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source", isDirectory: true)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try git(["init", source.path])
    try git(["-C", source.path, "config", "user.email", "test@example.com"])
    try git(["-C", source.path, "config", "user.name", "Aizen Test"])
    try "seed".write(to: source.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
    try git(["-C", source.path, "add", "README.md"])
    try git(["-C", source.path, "commit", "-m", "seed"])
    let service = GitLinkedWorktreeService()
    let clone = root.appendingPathComponent("clone", isDirectory: true)
    let copy = root.appendingPathComponent("copy", isDirectory: true)

    try await service.createIndependentContext(source: source, destination: clone, mode: .clone)
    try await service.createIndependentContext(source: source, destination: copy, mode: .copy)

    #expect(FileManager.default.fileExists(atPath: clone.appendingPathComponent(".git").path))
    #expect(FileManager.default.fileExists(atPath: copy.appendingPathComponent("README.md").path))
    #expect(!FileManager.default.fileExists(atPath: copy.appendingPathComponent(".git").path))
}

private func git(_ arguments: [String]) throws {
    _ = try gitOutput(arguments)
}

private func gitOutput(_ arguments: [String]) throws -> String {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw CocoaError(.executableNotLoadable) }
    return String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

@Test func hostAgentLaunchConfigurationKeepsEnvironmentOutOfTheConfigurationFile() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let secrets = RecordingEnvironmentStore()
    let store = HostAgentLaunchConfigurationStore(
        configurationURL: root.appendingPathComponent("host-agent-launch.json"),
        secrets: secrets
    )
    let command = ConfigureAgentLaunchCommandPayload(
        executablePath: "/usr/bin/env",
        arguments: ["codex-acp"],
        environment: ["TOKEN": "secret"]
    )

    try await store.updateAgentLaunchConfiguration(command)

    #expect(try await store.launchConfiguration() == ACPAgentLaunchConfiguration(
        executablePath: "/usr/bin/env",
        arguments: ["codex-acp"],
        environment: ["TOKEN": "secret"]
    ))
    #expect(String(decoding: try Data(contentsOf: root.appendingPathComponent("host-agent-launch.json")), as: UTF8.self).contains("secret") == false)
}

@Test func xpcWireServiceRoundTripsTheWireEnvelope() async throws {
    let request = ProtocolEnvelope(
        messageID: "xpc-round-trip",
        connectionSequence: 1,
        kind: .command,
        channel: .state,
        payload: try .init(ListSpacesQueryPayload())
    )
    let requestData = try request.serializedData()
    let service = XPCWireService(endpoint: EchoWireEndpoint())
    let responseData: Data = try await withCheckedThrowingContinuation { continuation in
        service.send(requestData) { data, error in
            if let error {
                continuation.resume(throwing: error)
            } else if let data {
                continuation.resume(returning: data)
            } else {
                continuation.resume(throwing: XPCWireTransportError.invalidResponse)
            }
        }
    }

    #expect(try ProtocolEnvelope(serializedData: responseData) == request)
}

@Test func xpcWireTransportRoundTripsThroughAnAcceptedConnection() async throws {
    let request = ProtocolEnvelope(
        messageID: "xpc-connection-round-trip",
        connectionSequence: 1,
        kind: .query,
        channel: .state,
        payload: try .init(ListSpacesQueryPayload())
    )
    let listener = XPCWireHostListener(wireEndpoint: EchoWireEndpoint())
    listener.resume()
    defer { listener.invalidate() }

    let endpoint = try #require(listener.listenerEndpoint)
    let response = try await XPCWireTransport(listenerEndpoint: endpoint).send(request)

    #expect(response == request)
}

@Test func acpRuntimeOwnsTheClientUntilTheRunIsCancelled() async throws {
    let client = RecordingClient()
    let runtime = ACPRunRuntime(
        configurationResolver: StaticConfigurationResolver(),
        delegateProvider: NoDelegateProvider(),
        clientFactory: StaticClientFactory(client: client)
    )
    let run = Run(spaceID: SpaceID(), sessionID: SessionID())
    try await runtime.start(run: run)
    #expect(await client.startedWorkingDirectory == "/tmp/aizen")
    #expect(try await runtime.send(message: "Hello", to: run.id, onAssistantTextDelta: { _ in }) == "Hello from ACP")
    #expect(await client.promptedText == "Hello")
    try await runtime.cancel(runID: run.id)
    #expect(await client.cancelledSessionID == "acp-session")
    #expect(await client.didTerminate)
}

@Test func storageBackedConfigurationUsesTheRunSandbox() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Vivy")
    let contextID = ExecutionContextID()
    let context = ExecutionContext(
        id: contextID,
        spaceID: space.id,
        kind: .managedTemporarySandbox,
        hostReference: HostPrivateReference(rawValue: "sandbox-\(contextID.description)")
    )
    let session = Session(spaceID: space.id, kind: .conversation, title: "Plan", executionContextID: context.id)
    _ = try await storage.transact {
        $0.spaces.append(space)
        $0.sessions.append(session)
        $0.executionContexts.append(context)
    }
    let run = Run(spaceID: space.id, sessionID: session.id, executionContextID: context.id)
    let resolver = StorageBackedACPRunConfigurationResolver(
        storage: storage,
        agentConfiguration: StaticAgentConfigurationResolver(),
        managedSandboxRoot: root.appendingPathComponent("sandboxes", isDirectory: true)
    )

    let configuration = try await resolver.configuration(for: run)
    #expect(configuration.executablePath == "/usr/bin/true")
    #expect(configuration.workingDirectory == root.appendingPathComponent("sandboxes").appendingPathComponent(space.id.description).appendingPathComponent(context.id.description).path)
}

@Test func storageBackedConfigurationUsesAHostOwnedLocalFolderResource() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("folder", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Vivy")
    let resource = Resource(spaceID: space.id, kind: .folder, title: "Folder", details: .hostPrivate(.init(rawValue: "local-folder:\(folder.path)")))
    let context = ExecutionContext(spaceID: space.id, kind: .localFolder, resourceID: resource.id, hostReference: .init(rawValue: "resource-context:\(resource.id.description)"))
    let session = Session(spaceID: space.id, kind: .conversation, title: "Plan", executionContextID: context.id)
    _ = try await storage.transact {
        $0.spaces.append(space)
        $0.resources.append(resource)
        $0.executionContexts.append(context)
        $0.sessions.append(session)
    }
    let resolver = StorageBackedACPRunConfigurationResolver(
        storage: storage,
        agentConfiguration: StaticAgentConfigurationResolver(),
        managedSandboxRoot: root.appendingPathComponent("sandboxes", isDirectory: true)
    )

    #expect(try await resolver.configuration(for: Run(spaceID: space.id, sessionID: session.id, executionContextID: context.id)).workingDirectory == folder.path)
}

@Test func storageBackedConfigurationUsesAHostOwnedRepositoryResource() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = root.appendingPathComponent("repository", isDirectory: true)
    try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Vivy")
    let resource = Resource(spaceID: space.id, kind: .repository, title: "Repository", details: .hostPrivate(.init(rawValue: "local-repository:\(repository.path)")))
    let context = ExecutionContext(spaceID: space.id, kind: .repositoryCheckout, resourceID: resource.id, hostReference: .init(rawValue: "repository-checkout:\(resource.id.description)"))
    let session = Session(spaceID: space.id, kind: .conversation, title: "Plan", executionContextID: context.id)
    _ = try await storage.transact {
        $0.spaces.append(space)
        $0.resources.append(resource)
        $0.executionContexts.append(context)
        $0.sessions.append(session)
    }
    let resolver = StorageBackedACPRunConfigurationResolver(storage: storage, agentConfiguration: StaticAgentConfigurationResolver(), managedSandboxRoot: root.appendingPathComponent("sandboxes", isDirectory: true))
    #expect(try await resolver.configuration(for: Run(spaceID: space.id, sessionID: session.id, executionContextID: context.id)).workingDirectory == repository.path)
}

@Test func storageBackedConfigurationUsesAHostOwnedLinkedWorktree() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let worktree = root.appendingPathComponent("worktree", isDirectory: true)
    try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Vivy")
    let resource = Resource(spaceID: space.id, kind: .repository, title: "Repository", details: .hostPrivate(.init(rawValue: "local-repository:\(root.path)")))
    let context = ExecutionContext(spaceID: space.id, kind: .gitWorktree, resourceID: resource.id, hostReference: .init(rawValue: "local-worktree:\(worktree.path)"))
    let session = Session(spaceID: space.id, kind: .conversation, title: "Plan", executionContextID: context.id)
    _ = try await storage.transact {
        $0.spaces.append(space)
        $0.resources.append(resource)
        $0.executionContexts.append(context)
        $0.sessions.append(session)
    }
    let resolver = StorageBackedACPRunConfigurationResolver(storage: storage, agentConfiguration: StaticAgentConfigurationResolver(), managedSandboxRoot: root.appendingPathComponent("sandboxes", isDirectory: true))
    #expect(try await resolver.configuration(for: Run(spaceID: space.id, sessionID: session.id, executionContextID: context.id)).workingDirectory == worktree.path)
}

@Test func storageBackedConfigurationUsesAHostOwnedIndependentContext() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let independentContext = root.appendingPathComponent("independent", isDirectory: true)
    try FileManager.default.createDirectory(at: independentContext, withIntermediateDirectories: true)
    let storage = StorageRepository(url: root.appendingPathComponent("storage-v2.json"))
    let space = Space(name: "Vivy")
    let resource = Resource(spaceID: space.id, kind: .repository, title: "Repository", details: .hostPrivate(.init(rawValue: "local-repository:\(root.path)")))
    let context = ExecutionContext(spaceID: space.id, kind: .copiedEnvironment, resourceID: resource.id, hostReference: .init(rawValue: "local-independent:\(independentContext.path)"))
    let session = Session(spaceID: space.id, kind: .conversation, title: "Plan", executionContextID: context.id)
    _ = try await storage.transact {
        $0.spaces.append(space)
        $0.resources.append(resource)
        $0.executionContexts.append(context)
        $0.sessions.append(session)
    }
    let resolver = StorageBackedACPRunConfigurationResolver(storage: storage, agentConfiguration: StaticAgentConfigurationResolver(), managedSandboxRoot: root.appendingPathComponent("sandboxes", isDirectory: true))
    #expect(try await resolver.configuration(for: Run(spaceID: space.id, sessionID: session.id, executionContextID: context.id)).workingDirectory == independentContext.path)
}

private func runGit(_ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
}

private struct StaticConfigurationResolver: ACPRunConfigurationResolving {
    func configuration(for run: Run) async throws -> ACPRunConfiguration {
        ACPRunConfiguration(executablePath: "/usr/bin/true", workingDirectory: "/tmp/aizen")
    }
}

private struct EchoWireEndpoint: WireEndpoint {
    func receive(_ envelope: ProtocolEnvelope) async throws -> ProtocolEnvelope {
        envelope
    }
}

private final class MemoryHostIdentityPersistence: @unchecked Sendable, HostIdentityPersisting {
    private let lock = NSLock()
    private var data: Data?

    func load() throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return data
    }

    func save(_ data: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        self.data = data
    }
}

private final class RecordingEnvironmentStore: @unchecked Sendable, HostAgentEnvironmentStoring {
    private var value: [String: String] = [:]

    func store(environment: [String: String]) throws {
        value = environment
    }

    func environment() throws -> [String: String] {
        value
    }
}

private struct NoDelegateProvider: ACPRunDelegateProviding {
    func delegate(for run: Run) async throws -> (any ACP.ClientDelegate)? { nil }
}

private struct StaticAgentConfigurationResolver: ACPAgentLaunchConfigurationResolving {
    func launchConfiguration() async throws -> ACPAgentLaunchConfiguration {
        ACPAgentLaunchConfiguration(executablePath: "/usr/bin/true")
    }
}

private struct StaticClientFactory: ACPRunClientFactory {
    let client: RecordingClient
    func makeClient() -> any ACPRunClient { client }
}

private actor RecordingClient: ACPRunClient {
    private(set) var startedWorkingDirectory: String?
    private(set) var cancelledSessionID: String?
    private(set) var promptedText: String?
    private(set) var didTerminate = false

    func start(configuration: ACPRunConfiguration, delegate: (any ACP.ClientDelegate)?) async throws -> String {
        startedWorkingDirectory = configuration.workingDirectory
        return "acp-session"
    }

    func sendPrompt(
        sessionID: String,
        text: String,
        onAssistantTextDelta: @escaping @Sendable (String) async -> Void
    ) async throws -> String? {
        promptedText = text
        await onAssistantTextDelta("Hello from ACP")
        return "Hello from ACP"
    }
    func cancel(sessionID: String) async throws { cancelledSessionID = sessionID }
    func terminate() async { didTerminate = true }
}
