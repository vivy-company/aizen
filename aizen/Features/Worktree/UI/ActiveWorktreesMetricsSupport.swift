//
//  ActiveWorktreesMetricsSupport.swift
//  aizen
//
//  Created by OpenAI Codex on 06.04.26.
//

import Darwin
import Foundation
import SwiftUI

struct ResourceSample {
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
