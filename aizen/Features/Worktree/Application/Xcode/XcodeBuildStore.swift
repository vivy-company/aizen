//
//  XcodeBuildStore.swift
//  aizen
//
//  Xcode build and run management
//

import Foundation
import SwiftUI
import Combine
import os.log

@MainActor
final class XcodeBuildStore: ObservableObject {
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "XcodeBuildStore")

    // MARK: - Published State

    @Published var currentPhase: BuildPhase = .idle
    @Published var detectedProject: XcodeProject?
    @Published var selectedScheme: String?
    @Published var selectedDestination: XcodeDestination?
    @Published var availableDestinations: [DestinationType: [XcodeDestination]] = [:]
    @Published var lastBuildLog: String?
    @Published var lastBuildDuration: TimeInterval?
    @Published var isLoadingDestinations = false
    @Published var isReady = false

    // Track launched app for termination before next launch
    @Published var launchedBundleId: String?
    @Published var launchedDestination: XcodeDestination?
    @Published var launchedAppPath: String?
    @Published var launchedPID: Int32?

    // For Mac apps launched directly, we keep the process and pipes to capture stdout/stderr
    var launchedProcess: Process?
    var launchedOutputPipe: Pipe?
    var launchedErrorPipe: Pipe?

    var appMonitorTask: Task<Void, Never>?

    // MARK: - Services

    let projectDetector = XcodeProjectDetector()
    let deviceService = XcodeDeviceService()
    let buildService = XcodeBuildService()

    var buildTask: Task<Void, Never>?
    var currentWorktreePath: String?
    var lastDestinationsRefreshAt: Date?
    let destinationsRefreshTTL: TimeInterval = 300

    init() {}

    // MARK: - Log Streaming

    @Published var isLogStreamActive = false
    @Published var logOutput: [String] = []

    let logService = XcodeLogService()
    var logStreamTask: Task<Void, Never>?
    var macLogStreamTask: Task<Void, Never>?
}
