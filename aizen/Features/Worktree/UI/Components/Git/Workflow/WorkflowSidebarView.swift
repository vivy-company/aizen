//
//  WorkflowSidebarView.swift
//  aizen
//
//  Sidebar view for workflow list and runs selection
//

import SwiftUI

struct WorkflowSidebarView: View {
    @ObservedObject var service: WorkflowService
    let onSelect: (Workflow) -> Void
    let onTrigger: (Workflow) -> Void

    var totalItemsCount: Int {
        service.workflows.count + service.runs.count
    }

    var body: some View {
        VStack(spacing: 0) {
            sidebarHeader
            GitWindowDivider()

            if service.isInitializing {
                initializingView
            } else if !service.isConfigured {
                noProviderView
            } else if !service.isCLIInstalled {
                cliNotInstalledView
            } else if !service.isAuthenticated {
                notAuthenticatedView
            } else {
                // Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        workflowsSection
                        runsSection
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
            }
            if let error = service.error {
                errorBanner(error)
            }
        }
    }
}
