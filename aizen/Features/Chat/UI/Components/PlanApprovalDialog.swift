//
//  PlanApprovalDialog.swift
//  aizen
//
//  Plan approval sheet and inline plan approval components
//

import AppKit
import ACP
import SwiftUI

struct PlanApprovalDialog: View {
    let session: ChatAgentSession?
    let request: RequestPermissionRequest
    @Binding var isPresented: Bool
    var showsActions: Bool = true

    var body: some View {
        dialogContent
    }
}

struct PermissionRequestPrompt {
    let title: String
    let detail: String?
}
