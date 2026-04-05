//
//  ActiveWorktreesMetrics.swift
//  aizen
//
//  App-level and host-level metrics sampling for Activity Monitor.
//

import Combine
import Darwin
import Foundation
import SwiftUI

@MainActor
final class ActiveWorktreesMetrics: ObservableObject {
    @Published var cpuPercent: Double = 0
    @Published var memoryBytes: UInt64 = 0
    @Published var energyScore: Double = 0

    @Published var userCPUPercent: Double = 0
    @Published var systemCPUPercent: Double = 0
    @Published var idleCPUPercent: Double = 100

    @Published var cpuHistory: [Double] = []
    @Published var memoryHistory: [UInt64] = []
    @Published var energyHistory: [Double] = []

    var task: Task<Void, Never>?
    var lastSample: ResourceSample?
    var lastHostSample: HostCPUSample?
    let maxHistoryCount = 60

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
