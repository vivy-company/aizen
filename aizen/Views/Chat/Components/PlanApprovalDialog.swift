//
//  PlanApprovalDialog.swift
//  aizen
//
//  Dialog for approving/rejecting agent plans
//

import SwiftUI

struct PlanApprovalDialog: View {
    @ObservedObject var session: AgentSession
    let request: RequestPermissionRequest
    @Binding var isPresented: Bool

    private var planContent: String? {
        guard let toolCall = request.toolCall,
              let rawInput = toolCall.rawInput?.value as? [String: Any],
              let plan = rawInput["plan"] as? String else {
            return nil
        }
        return plan
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "list.clipboard")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.blue)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Review Plan")
                        .font(.headline)
                    Text("The agent wants to execute this plan")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color(nsColor: .separatorColor).opacity(0.5), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            // Plan content
            ScrollView {
                if let planContent = planContent {
                    PlanContentView(content: planContent)
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(Color(nsColor: .textBackgroundColor))

            // Action buttons
            HStack(spacing: 10) {
                if let options = request.options {
                    ForEach(options, id: \.optionId) { option in
                        Button {
                            session.respondToPermission(optionId: option.optionId)
                            isPresented = false
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: buttonIcon(for: option))
                                    .font(.system(size: 12, weight: .semibold))
                                Text(option.name)
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundStyle(buttonForeground(for: option))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(buttonBackground(for: option))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 580, height: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 30, y: 15)
    }

    private func buttonIcon(for option: PermissionOption) -> String {
        if option.kind == "allow_always" {
            return "checkmark.circle.fill"
        } else if option.kind.contains("allow") {
            return "checkmark"
        } else if option.kind.contains("reject") {
            return "xmark"
        }
        return "circle"
    }

    private func buttonForeground(for option: PermissionOption) -> Color {
        if option.kind.contains("allow") || option.kind.contains("reject") {
            return .white
        }
        return .primary
    }

    private func buttonBackground(for option: PermissionOption) -> Color {
        if option.kind == "allow_always" {
            return .green
        } else if option.kind.contains("allow") {
            return .blue
        } else if option.kind.contains("reject") {
            return .red.opacity(0.85)
        }
        return .secondary.opacity(0.2)
    }
}
