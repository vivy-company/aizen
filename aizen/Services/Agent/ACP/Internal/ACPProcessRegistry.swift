//
//  ACPProcessRegistry.swift
//  aizen
//
//  Tracks ACP agent processes across launches for crash recovery cleanup.
//

import Foundation
import Darwin
import os.log

actor ACPProcessRegistry {
    static let shared = ACPProcessRegistry()

    private let logger = Logger.forCategory("ACPProcessRegistry")
    private let registryURL: URL
    private let maxEntryAge: TimeInterval = 60 * 60 * 24 * 7 // 7 days

    struct Entry: Codable, Equatable {
        let pid: Int32
        let pgid: Int32?
        let agentPath: String
        let startedAt: TimeInterval
    }

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("Aizen/ACP", isDirectory: true)
        registryURL = directory.appendingPathComponent("acp-processes.json")

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create ACP registry directory: \(error.localizedDescription)")
        }
    }

    func recordProcess(pid: Int32, pgid: Int32?, agentPath: String) {
        var entries = loadEntries()
        entries.removeAll { $0.pid == pid || ($0.pgid != nil && $0.pgid == pgid) }
        entries.append(Entry(pid: pid, pgid: pgid, agentPath: agentPath, startedAt: Date().timeIntervalSince1970))
        writeEntries(entries)
    }

    func removeProcess(pid: Int32?, pgid: Int32?) {
        guard pid != nil || pgid != nil else { return }
        var entries = loadEntries()
        entries.removeAll { entry in
            if let pid, entry.pid == pid { return true }
            if let pgid, entry.pgid == pgid { return true }
            return false
        }
        writeEntries(entries)
    }

    func cleanupOrphanedProcesses() async {
        var entries = loadEntries()
        guard !entries.isEmpty else { return }

        let now = Date().timeIntervalSince1970
        var remaining: [Entry] = []

        for entry in entries {
            if now - entry.startedAt > maxEntryAge {
                continue
            }

            let processes = fetchProcesses(for: entry)
            if processes.isEmpty {
                continue
            }

            guard matchesExpectedProcess(entry: entry, processes: processes) else {
                logger.info("Skipping orphan cleanup for pid=\(entry.pid) pgid=\(entry.pgid ?? -1): command mismatch")
                remaining.append(entry)
                continue
            }

            let targetId = entry.pgid ?? entry.pid
            if entry.pgid != nil {
                _ = killpg(targetId, SIGTERM)
            } else {
                _ = kill(targetId, SIGTERM)
            }

            let exited = await waitForExit(entry: entry, timeout: 2.0)
            if !exited {
                if entry.pgid != nil {
                    _ = killpg(targetId, SIGKILL)
                } else {
                    _ = kill(targetId, SIGKILL)
                }
                let killed = await waitForExit(entry: entry, timeout: 1.0)
                if !killed {
                    remaining.append(entry)
                }
            }
        }

        writeEntries(remaining)
    }

    // MARK: - Private helpers

    private func loadEntries() -> [Entry] {
        guard let data = try? Data(contentsOf: registryURL) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    private func writeEntries(_ entries: [Entry]) {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: registryURL, options: [.atomic])
        } catch {
            logger.error("Failed to write ACP registry: \(error.localizedDescription)")
        }
    }

    private func matchesExpectedProcess(entry: Entry, processes: [(pid: Int32, command: String)]) -> Bool {
        let expectedPath = entry.agentPath
        return processes.contains { $0.command.contains(expectedPath) }
    }

    private func fetchProcesses(for entry: Entry) -> [(pid: Int32, command: String)] {
        if let pgid = entry.pgid {
            return fetchProcessesByGroup(pgid)
        }
        return fetchProcessesByPid(entry.pid)
    }

    private func fetchProcessesByGroup(_ pgid: Int32) -> [(pid: Int32, command: String)] {
        return parsePsOutput(args: ["-o", "pid=,command=", "-g", String(pgid)])
    }

    private func fetchProcessesByPid(_ pid: Int32) -> [(pid: Int32, command: String)] {
        return parsePsOutput(args: ["-o", "pid=,command=", "-p", String(pid)])
    }

    private func parsePsOutput(args: [String]) -> [(pid: Int32, command: String)] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = args

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        guard let data = try? outputPipe.fileHandleForReading.read(upToCount: 1_000_000),
              let output = String(data: data, encoding: .utf8) else {
            return []
        }

        let lines = output.split(separator: "\n")
        var results: [(pid: Int32, command: String)] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let parts = trimmed.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
            guard let pidValue = parts.first, let pid = Int32(pidValue) else { continue }
            let command = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
            results.append((pid: pid, command: command))
        }

        return results
    }

    private func waitForExit(entry: Entry, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !isAlive(entry: entry) {
                return true
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return !isAlive(entry: entry)
    }

    private func isAlive(entry: Entry) -> Bool {
        if let pgid = entry.pgid {
            if killpg(pgid, 0) == 0 { return true }
            return errno == EPERM
        }
        if kill(entry.pid, 0) == 0 { return true }
        return errno == EPERM
    }
}
