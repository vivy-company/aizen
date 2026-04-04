import Foundation

extension AgentTerminalDelegate {
    func cachedReleasedOutput(for terminalId: String) -> String? {
        releasedOutputs[terminalId]?.output
    }

    func clearReleasedOutputs() {
        releasedOutputs.removeAll()
        releasedOutputOrder.removeAll()
    }

    func cacheReleasedOutput(terminalId: String, output: String, exitCode: Int) {
        releasedOutputs[terminalId] = ReleasedTerminalOutput(output: output, exitCode: exitCode)
        releasedOutputOrder.removeAll { $0 == terminalId }
        releasedOutputOrder.append(terminalId)

        while releasedOutputOrder.count > maxReleasedOutputEntries,
              let oldest = releasedOutputOrder.first {
            releasedOutputOrder.removeFirst()
            releasedOutputs.removeValue(forKey: oldest)
        }
    }
}
