import CoreData
import SwiftUI

enum ActiveWorktreesMonitorMode: String, CaseIterable, Identifiable {
    case chats
    case terminals
    case files
    case browsers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chats: return "Chats"
        case .terminals: return "Terminals"
        case .files: return "Files"
        case .browsers: return "Browsers"
        }
    }

    var tintColor: Color {
        switch self {
        case .chats: return .blue
        case .terminals: return .green
        case .files: return .orange
        case .browsers: return .teal
        }
    }
}

enum ActiveWorktreesScopeSelection: Hashable {
    case all
    case workspace(NSManagedObjectID)
    case other
}

struct ActiveWorktreesWorkspaceGroup: Identifiable {
    let id: String
    let workspaceId: NSManagedObjectID?
    let name: String
    let colorHex: String?
    let order: Int
    var worktrees: [Worktree]
    let isOther: Bool
}

struct ActiveWorktreesSessionCounts {
    var chats: Int = 0
    var terminals: Int = 0
    var browsers: Int = 0
    var files: Int = 0

    var total: Int {
        chats + terminals + browsers + files
    }
}

struct ActiveWorktreesMonitorRowSeed {
    let id: String
    let worktree: Worktree
    let processName: String
    let workspaceName: String
    let path: String
    let counts: ActiveWorktreesSessionCounts
    let runtime: ActiveWorktreesTerminalRuntimeSnapshot
    let lastAccessed: Date
}

struct ActiveWorktreesMonitorRow: Identifiable {
    let id: String
    let worktree: Worktree
    let processName: String
    let workspaceName: String
    let path: String
    let cpuPercent: Double
    let memoryBytes: UInt64
    let energyImpact: Double
    let threadCount: Int
    let idleWakeUps: Int
    let totalSessions: Int
    let counts: ActiveWorktreesSessionCounts
    let runtime: ActiveWorktreesTerminalRuntimeSnapshot
    let lastAccessed: Date

    var chatSessions: Int { counts.chats }
    var terminalSessions: Int { counts.terminals }
    var fileSessions: Int { counts.files }
    var browserSessions: Int { counts.browsers }
    var runningPanes: Int { runtime.runningPanes }
    var livePanes: Int { runtime.livePanes }
    var terminalStateSortOrder: Int {
        switch terminalStatus {
        case .running: return 3
        case .ready: return 2
        case .detached: return 1
        case .none: return 0
        }
    }

    var terminalStatus: ActiveWorktreesTerminalState {
        if counts.terminals == 0 {
            return .none
        }

        if runtime.runningPanes > 0 {
            return .running
        }

        if runtime.livePanes > 0 {
            return .ready
        }

        if runtime.expectedPanes > 0 {
            return .detached
        }

        return .none
    }
}

struct ActiveWorktreesTerminalRuntimeSnapshot {
    let expectedPanes: Int
    let livePanes: Int
    let runningPanes: Int
}

enum ActiveWorktreesTerminalState {
    case running
    case ready
    case detached
    case none

    var title: String {
        switch self {
        case .running: return "Running"
        case .ready: return "Ready"
        case .detached: return "Detached"
        case .none: return "None"
        }
    }

    var color: Color {
        switch self {
        case .running: return .green
        case .ready: return .blue
        case .detached: return .orange
        case .none: return .secondary
        }
    }
}
