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
        guard let toolCall = request.toolCall,
              let rawInput = toolCall.rawInput?.value as? [String: Any],
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

    var pendingPlanTimelineRequestIdentity: String {
        guard let request = pendingPlanTimelineRequest else { return "none" }
        let optionIds = (request.options ?? []).map(\.optionId).joined(separator: "|")
        let toolId = request.toolCall?.toolCallId ?? "none"
        return "req-\(toolId)-\(optionIds)-\(request.message ?? "")"
    }

    var timelineRenderKey: ChatTimelineRenderKey {
        ChatTimelineRenderKey(
            timelineRenderEpoch: viewModel.timelineRenderEpoch,
            isSessionInitializing: viewModel.isSessionInitializing,
            pendingPlanRequestIdentity: pendingPlanTimelineRequestIdentity,
            selectedAgent: viewModel.selectedAgent,
            scrollRequestId: viewModel.scrollRequest?.id
        )
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
