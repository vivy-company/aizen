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

// MARK: - Selectable Row Modifier with Liquid Glass

struct SelectableRowModifier: ViewModifier {
    let isSelected: Bool
    let isHovered: Bool
    var showsIdleBackground: Bool = true
    var cornerRadius: CGFloat = 8

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(macOS 26.0, *) {
            content
                .background {
                    if isSelected {
                        GlassEffectContainer {
                            shape
                                .fill(.white.opacity(0.001))
                                .glassEffect(.regular.tint(.accentColor.opacity(0.24)).interactive(), in: shape)
                            shape
                                .fill(Color.accentColor.opacity(0.10))
                        }
                    } else if isHovered {
                        shape
                            .fill(Color.white.opacity(0.05))
                    } else if showsIdleBackground {
                        shape
                            .fill(Color.white.opacity(0.02))
                    }
                }
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            isSelected
                                ? Color(nsColor: .selectedContentBackgroundColor)
                                : (isHovered ? Color.white.opacity(0.06) : (showsIdleBackground ? Color.white.opacity(0.02) : .clear))
                        )
                )
        }
    }
}
