import Foundation

@MainActor
extension ActiveWorktreesMetrics {
    var maxMemoryHistoryBytes: UInt64 {
        memoryHistory.max() ?? max(memoryBytes, 1)
    }

    var energyLabel: String {
        if energyScore < 20 { return "Low" }
        if energyScore < 50 { return "Medium" }
        if energyScore < 80 { return "High" }
        return "Very High"
    }
}
