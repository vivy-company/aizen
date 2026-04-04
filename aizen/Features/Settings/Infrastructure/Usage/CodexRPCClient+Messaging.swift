//
//  CodexRPCClient+Messaging.swift
//  aizen
//
//  JSON-RPC wire messaging and decoding for codex app-server
//

import Foundation

extension CodexRPCClient {
    // SAFETY: Thread-safe via NSLock protecting buffer mutations.
    final class LineBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var buffer = Data()

        func appendAndDrainLines(_ data: Data) -> [Data] {
            lock.lock()
            defer { lock.unlock() }

            buffer.append(data)
            var out: [Data] = []
            while let newline = buffer.firstIndex(of: 0x0A) {
                let lineData = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                if !lineData.isEmpty {
                    out.append(lineData)
                }
            }
            return out
        }
    }

    func request(method: String, params: [String: Any]? = nil) async throws -> [String: Any] {
        let id = nextID
        nextID += 1
        try sendRequest(id: id, method: method, params: params)

        while true {
            let message = try await readNextMessage()

            if message["id"] == nil, message["method"] != nil {
                continue
            }

            guard let messageID = jsonID(message["id"]), messageID == id else { continue }

            if let error = message["error"] as? [String: Any], let messageText = error["message"] as? String {
                throw RPCWireError.requestFailed(messageText)
            }

            return message
        }
    }

    func sendNotification(method: String, params: [String: Any]? = nil) throws {
        try sendMessage([
            "method": method,
            "params": params ?? [:],
        ])
    }

    func sendRequest(id: Int, method: String, params: [String: Any]? = nil) throws {
        try sendMessage([
            "id": id,
            "method": method,
            "params": params ?? [:],
        ])
    }

    func sendMessage(_ message: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: message)
        var buffer = data
        buffer.append(0x0A)
        try stdinPipe.fileHandleForWriting.write(contentsOf: buffer)
    }

    func readNextMessage() async throws -> [String: Any] {
        for await line in stdoutLineStream {
            if let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                return obj
            }
        }
        if let summary = stderrSummary() {
            throw RPCWireError.malformed("codex app-server closed stdout. \(summary)")
        }
        throw RPCWireError.malformed("codex app-server closed stdout")
    }

    func jsonID(_ raw: Any?) -> Int? {
        if let number = raw as? NSNumber { return number.intValue }
        if let string = raw as? String, let number = Int(string) { return number }
        return nil
    }

    func decodeResult<T: Decodable>(from message: [String: Any], as type: T.Type) throws -> T {
        guard let result = message["result"] else {
            throw RPCWireError.malformed("Missing result")
        }
        let data = try JSONSerialization.data(withJSONObject: result)
        return try JSONDecoder().decode(T.self, from: data)
    }

    func recordStderr(_ line: String) {
        stderrLock.lock()
        defer { stderrLock.unlock() }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        stderrLines.append(trimmed)
        if stderrLines.count > stderrLimit {
            stderrLines.removeFirst(stderrLines.count - stderrLimit)
        }
    }

    func stderrSummary() -> String? {
        stderrLock.lock()
        defer { stderrLock.unlock() }
        guard !stderrLines.isEmpty else { return nil }
        return "stderr: " + stderrLines.joined(separator: " | ")
    }
}
