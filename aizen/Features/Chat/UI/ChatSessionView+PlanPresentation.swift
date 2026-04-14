//
//  ChatSessionView+PlanPresentation.swift
//  aizen
//
//  Pending plan request and inline plan presentation helpers.
//

import ACP
import SwiftUI
import VVChatTimeline

extension ChatSessionView {
    func isPlanRequest(_ request: RequestPermissionRequest) -> Bool {
        guard let rawInput = request.toolCall.rawInput?.value as? [String: Any],
              let _ = rawInput["plan"] as? String else {
            return false
        }
        return true
    }

    var pendingPlanTimelineRequest: RequestPermissionRequest? {
        guard let request = viewModel.currentPermissionRequest,
              isPlanRequest(request) else {
            return nil
        }
        return request
    }

    var inlinePlan: Plan? {
        guard pendingPlanTimelineRequest == nil,
              let plan = viewModel.currentAgentPlan,
              !plan.entries.isEmpty else {
            return nil
        }

        let completedCount = plan.entries.filter { $0.status == .completed }.count
        guard completedCount < plan.entries.count else {
            return nil
        }

        return plan
    }

    var shouldAttachInlinePlanToInput: Bool {
        inlinePlan != nil && viewModel.attachments.isEmpty
    }

    var inlinePlanWidth: CGFloat? {
        guard shouldAttachInlinePlanToInput, inputBarWidth > 0 else {
            return nil
        }
        return inputBarWidth * 0.95
    }
}
