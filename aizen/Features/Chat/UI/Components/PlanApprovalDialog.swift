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

                CircleIconButton(
                    systemName: "xmark",
                    action: { isPresented = false },
                    size: 12,
                    weight: .semibold,
                    foreground: .secondary,
                    backgroundColor: Color(nsColor: .separatorColor),
                    backgroundOpacity: 0.5,
                    frameSize: 24
                )
            }
            .padding(20)

            ScrollView {
                if let planContent = planContent {
                    PlanContentView(content: planContent)
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Plan content is unavailable.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(Color(nsColor: .textBackgroundColor))

            if showsActions {
                HStack(spacing: 10) {
                    if let options = request.options {
                        ForEach(options, id: \.optionId) { option in
                            Button {
                                session?.respondToPermission(optionId: option.optionId)
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
                            .disabled(session == nil)
                        }
                    }
                }
                .padding(16)
                .background(AppSurfaceTheme.backgroundColor())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppSurfaceTheme.backgroundColor())
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 30, y: 15)
    }
}

struct PermissionRequestPrompt {
    let title: String
    let detail: String?
}
