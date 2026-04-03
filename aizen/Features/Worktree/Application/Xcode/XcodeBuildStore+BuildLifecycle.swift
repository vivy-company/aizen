//
//  XcodeBuildStore+BuildLifecycle.swift
//  aizen
//
//  Build execution and reset lifecycle
//

import Foundation
import os

extension XcodeBuildStore {
    func buildAndRun() {
        guard let project = detectedProject,
              let scheme = selectedScheme,
              let destination = selectedDestination else {
            logger.warning("Cannot build: missing project, scheme, or destination")
            return
        }

        cancelBuild()

        let startTime = Date()
        let buildService = self.buildService

        buildTask = Task { [weak self] in
            guard let self = self else { return }

            for await phase in await buildService.buildAndRun(
                project: project,
                scheme: scheme,
                destination: destination
            ) {
                await MainActor.run {
                    self.currentPhase = phase

                    if case .failed(_, let log) = phase {
                        self.lastBuildLog = log
                        self.lastBuildDuration = Date().timeIntervalSince(startTime)
                    }

                    if case .succeeded = phase {
                        self.lastBuildDuration = Date().timeIntervalSince(startTime)
                        self.lastBuildLog = nil

                        if destination.type == .simulator {
                            Task {
                                await self.launchInSimulator(project: project, scheme: scheme, destination: destination)
                            }
                        } else if destination.type == .mac {
                            Task {
                                await self.launchOnMac(project: project, scheme: scheme)
                            }
                        } else if destination.type == .device {
                            Task {
                                await self.launchOnDevice(project: project, scheme: scheme, destination: destination)
                            }
                        }
                    }
                }
            }
        }
    }

    func cancelBuild() {
        buildTask?.cancel()
        buildTask = nil
        Task {
            await buildService.cancelBuild()
        }
        if currentPhase.isBuilding {
            currentPhase = .idle
        }
    }

    func resetStatus() {
        if !currentPhase.isBuilding {
            currentPhase = .idle
            lastBuildLog = nil
        }
    }
}
