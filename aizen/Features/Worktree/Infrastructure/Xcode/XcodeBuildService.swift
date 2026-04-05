//
//  XcodeBuildService.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 10.12.25.
//

import Foundation
import os.log

actor XcodeBuildService {
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "XcodeBuildService")

    var currentProcess: Process?
    var isCancelled = false

    // MARK: - Build and Run

    func buildAndRun(
        project: XcodeProject,
        scheme: String,
        destination: XcodeDestination
    ) -> AsyncStream<BuildPhase> {
        AsyncStream { continuation in
            Task {
                await self.executeBuild(
                    project: project,
                    scheme: scheme,
                    destination: destination,
                    continuation: continuation
                )
            }
        }
    }

    // MARK: - Cancel

    func cancelBuild() {
        isCancelled = true
        currentProcess?.terminate()
    }

}
