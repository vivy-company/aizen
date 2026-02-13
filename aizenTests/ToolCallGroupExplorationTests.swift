//
//  ToolCallGroupExplorationTests.swift
//  aizenTests
//

import ACP
import Foundation
import Testing
@testable import aizen

struct ToolCallGroupExplorationTests {
    @Test func groupsConsecutiveReadCallsIntoSingleExplorationCluster() {
        let calls = [
            makeToolCall(id: "c1", kind: .read, title: "/repo/A.swift", timestampOffset: 0),
            makeToolCall(id: "c2", kind: .read, title: "/repo/B.swift", timestampOffset: 1),
            makeToolCall(id: "c3", kind: .read, title: "/repo/B.swift", timestampOffset: 2)
        ]

        let group = ToolCallGroup(iterationId: "it-1", toolCalls: calls)
        #expect(group.displayItems.count == 1)

        guard let first = group.displayItems.first else {
            #expect(false)
            return
        }

        guard case .exploration(let cluster) = first else {
            #expect(false)
            return
        }

        #expect(cluster.toolCalls.count == 3)
        #expect(cluster.fileCount == 2)
        #expect(cluster.summaryText == "Explored 2 files")
    }

    @Test func endsExplorationGroupWhenNonExplorationCallAppears() {
        let calls = [
            makeToolCall(id: "c1", kind: .read, title: "/repo/A.swift", timestampOffset: 0),
            makeToolCall(id: "c2", kind: .edit, title: "/repo/C.swift", timestampOffset: 1),
            makeToolCall(id: "c3", kind: .read, title: "/repo/D.swift", timestampOffset: 2)
        ]

        let group = ToolCallGroup(iterationId: "it-2", toolCalls: calls)
        #expect(group.displayItems.count == 3)

        guard case .exploration = group.displayItems[0] else {
            #expect(false)
            return
        }
        guard case .toolCall(let editCall) = group.displayItems[1] else {
            #expect(false)
            return
        }
        #expect(editCall.kind == .edit)
        guard case .exploration = group.displayItems[2] else {
            #expect(false)
            return
        }
    }

    @Test func usesSingularSummaryWhenOneUniquePath() {
        let calls = [
            makeToolCall(id: "c1", kind: .read, title: "/repo/A.swift", timestampOffset: 0),
            makeToolCall(id: "c2", kind: .read, title: "/repo/A.swift", timestampOffset: 1)
        ]

        let group = ToolCallGroup(iterationId: "it-3", toolCalls: calls)
        guard case .exploration(let cluster) = group.displayItems.first else {
            #expect(false)
            return
        }

        #expect(cluster.fileCount == 1)
        #expect(cluster.summaryText == "Explored 1 file")
    }

    @Test func groupsSearchAndGrepCallsWhenKindsAreAvailable() {
        guard let searchKind = ToolKind(rawValue: "search"),
              let grepKind = ToolKind(rawValue: "grep") else {
            return
        }

        let calls = [
            makeToolCall(id: "c1", kind: searchKind, title: "/repo/A.swift", timestampOffset: 0),
            makeToolCall(id: "c2", kind: grepKind, title: "/repo/B.swift", timestampOffset: 1)
        ]

        let group = ToolCallGroup(iterationId: "it-4", toolCalls: calls)
        #expect(group.displayItems.count == 1)

        guard case .exploration(let cluster) = group.displayItems[0] else {
            #expect(false)
            return
        }

        #expect(cluster.fileCount == 2)
    }

    @Test func summaryTextUsesExplorationLabelWhenGroupContainsOnlyExplorationCalls() {
        let calls = [
            makeToolCall(id: "c1", kind: .read, title: "/repo/A.swift", timestampOffset: 0),
            makeToolCall(id: "c2", kind: .read, title: "/repo/B.swift", timestampOffset: 1)
        ]

        let group = ToolCallGroup(iterationId: "it-5", toolCalls: calls)
        #expect(group.summaryText == "Explored 2 files")
    }

    @Test func groupsListExecuteCallWithExplorationCalls() {
        let calls = [
            makeToolCall(id: "c1", kind: .read, title: "/repo/A.swift", timestampOffset: 0),
            makeToolCall(id: "c2", kind: .execute, title: "List Swift files in the project", timestampOffset: 1)
        ]

        let group = ToolCallGroup(iterationId: "it-6", toolCalls: calls)
        #expect(group.displayItems.count == 1)
        #expect(group.summaryText == "Explored 1 file")
    }
}

private func makeToolCall(
    id: String,
    kind: ToolKind?,
    title: String,
    timestampOffset: TimeInterval
) -> ToolCall {
    ToolCall(
        toolCallId: id,
        title: title,
        kind: kind,
        status: .completed,
        content: [],
        locations: nil,
        rawInput: nil,
        rawOutput: nil,
        timestamp: Date(timeIntervalSince1970: 1_000 + timestampOffset)
    )
}
