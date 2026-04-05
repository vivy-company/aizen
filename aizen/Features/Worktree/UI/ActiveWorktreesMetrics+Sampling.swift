import Foundation

@MainActor
extension ActiveWorktreesMetrics {
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

    func sample() {
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

    func updateHostCPUPercentages() {
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

        let user = (Double(userDelta) + Double(niceDelta)) / Double(total) * 100
        let system = Double(systemDelta) / Double(total) * 100
        let idle = Double(idleDelta) / Double(total) * 100

        userCPUPercent = max(0, user)
        systemCPUPercent = max(0, system)
        idleCPUPercent = max(0, idle)
    }

    func appendHistory(cpu: Double, memory: UInt64, energy: Double) {
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
