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

    private var task: Task<Void, Never>?
    private var lastSample: ResourceSample?
    private var lastHostSample: HostCPUSample?
    private let maxHistoryCount = 60

    var maxMemoryHistoryBytes: UInt64 {
        memoryHistory.max() ?? max(memoryBytes, 1)
    }

    var energyLabel: String {
        if energyScore < 20 { return "Low" }
        if energyScore < 50 { return "Medium" }
        if energyScore < 80 { return "High" }
        return "Very High"
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                self.sample()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func refreshNow() {
        sample()
    }

    private func sample() {
        let now = Date()
        let cpuTime = SystemMetrics.currentCPUTime()
        let memory = SystemMetrics.currentMemoryBytes()
        let sample = ResourceSample(timestamp: now, cpuTime: cpuTime)

        if let last = lastSample {
            let deltaTime = now.timeIntervalSince(last.timestamp)
            let deltaCPU = cpuTime - last.cpuTime
            let cpu = SystemMetrics.cpuPercent(deltaCPU: deltaCPU, deltaTime: deltaTime)
            cpuPercent = max(0, cpu)
        }

        memoryBytes = memory
        energyScore = SystemMetrics.energyScore(cpuPercent: cpuPercent)
        updateHostCPUPercentages()

        appendHistory(cpu: cpuPercent, memory: memoryBytes, energy: energyScore)
        lastSample = sample
    }

    private func updateHostCPUPercentages() {
        guard let current = SystemMetrics.currentHostCPUTicks() else {
            userCPUPercent = cpuPercent
            systemCPUPercent = min(100 - userCPUPercent, cpuPercent * 0.4)
            idleCPUPercent = max(0, 100 - userCPUPercent - systemCPUPercent)
            return
        }

        defer { lastHostSample = current }
        guard let previous = lastHostSample else {
            return
        }

        let userDelta = current.user >= previous.user ? current.user - previous.user : 0
        let niceDelta = current.nice >= previous.nice ? current.nice - previous.nice : 0
        let systemDelta = current.system >= previous.system ? current.system - previous.system : 0
        let idleDelta = current.idle >= previous.idle ? current.idle - previous.idle : 0

        let total = userDelta + niceDelta + systemDelta + idleDelta
        guard total > 0 else { return }

        let user = Double(userDelta + niceDelta) / Double(total) * 100
        let system = Double(systemDelta) / Double(total) * 100
        let idle = Double(idleDelta) / Double(total) * 100

        userCPUPercent = max(0, user)
        systemCPUPercent = max(0, system)
        idleCPUPercent = max(0, idle)
    }

    private func appendHistory(cpu: Double, memory: UInt64, energy: Double) {
        cpuHistory.append(cpu)
        memoryHistory.append(memory)
        energyHistory.append(energy)

        if cpuHistory.count > maxHistoryCount {
            cpuHistory.removeFirst(cpuHistory.count - maxHistoryCount)
        }
        if memoryHistory.count > maxHistoryCount {
            memoryHistory.removeFirst(memoryHistory.count - maxHistoryCount)
        }
        if energyHistory.count > maxHistoryCount {
            energyHistory.removeFirst(energyHistory.count - maxHistoryCount)
        }
    }
}

private struct ResourceSample {
    let timestamp: Date
    let cpuTime: TimeInterval
}

struct HostCPUSample {
    let user: UInt64
    let system: UInt64
    let idle: UInt64
    let nice: UInt64
}

enum SystemMetrics {
    static func currentCPUTime() -> TimeInterval {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
        let user = TimeInterval(usage.ru_utime.tv_sec) + TimeInterval(usage.ru_utime.tv_usec) / 1_000_000
        let system = TimeInterval(usage.ru_stime.tv_sec) + TimeInterval(usage.ru_stime.tv_usec) / 1_000_000
        return user + system
    }

    static func currentMemoryBytes() -> UInt64 {
        var info = mach_task_basic_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.size) / 4
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard kerr == KERN_SUCCESS else { return 0 }
        return UInt64(info.resident_size)
    }

    static func currentHostCPUTicks() -> HostCPUSample? {
        var load = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result: kern_return_t = withUnsafeMutablePointer(to: &load) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebounded in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, rebounded, &count)
            }
        }

        guard result == KERN_SUCCESS else { return nil }

        return HostCPUSample(
            user: UInt64(load.cpu_ticks.0),
            system: UInt64(load.cpu_ticks.1),
            idle: UInt64(load.cpu_ticks.2),
            nice: UInt64(load.cpu_ticks.3)
        )
    }

    static func cpuPercent(deltaCPU: TimeInterval, deltaTime: TimeInterval) -> Double {
        guard deltaTime > 0 else { return 0 }
        let coreCount = max(1, ProcessInfo.processInfo.activeProcessorCount)
        return (deltaCPU / (deltaTime * Double(coreCount))) * 100.0
    }

    static func energyScore(cpuPercent: Double) -> Double {
        min(100.0, cpuPercent * 1.5)
    }
}

extension UInt64 {
    func formattedBytes() -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(self))
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let lineColor: Color
    let history: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Sparkline(history: history, lineColor: lineColor)
                .frame(height: 24)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
        )
        .cornerRadius(8)
    }
}

struct Sparkline: View {
    let history: [Double]
    let lineColor: Color

    var body: some View {
        GeometryReader { geo in
            let points = normalized(history)
            Path { path in
                guard points.count > 1 else { return }
                let stepX = geo.size.width / CGFloat(points.count - 1)
                let height = geo.size.height
                path.move(to: CGPoint(x: 0, y: height * (1 - points[0])))
                for index in points.indices.dropFirst() {
                    let x = CGFloat(index) * stepX
                    let y = height * (1 - points[index])
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            .stroke(lineColor, lineWidth: 1.5)
            .background(
                Rectangle().fill(lineColor.opacity(0.08))
            )
            .cornerRadius(4)
        }
    }

    private func normalized(_ values: [Double]) -> [Double] {
        values.map { min(max($0, 0), 1) }
    }
}

struct ActivityMeter: View {
    let score: Double

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: width, height: height)
                RoundedRectangle(cornerRadius: 4)
                    .fill(color)
                    .frame(width: width * CGFloat(score / 100.0), height: height)
            }
        }
        .frame(height: 8)
        .overlay(
            Text("\(Int(score))")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 12),
            alignment: .topLeading
        )
    }

    private var color: Color {
        if score < 30 { return .green }
        if score < 70 { return .orange }
        return .red
    }
}
