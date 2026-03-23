//
//  PermissionRequestView.swift
//  aizen
//
//  Permission request UI
//

import ACP
import SwiftUI

struct PermissionRequestView: View {
    @ObservedObject var session: AgentSession
    let request: RequestPermissionRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let prompt = request.promptDescription

            VStack(alignment: .leading, spacing: 4) {
                Text(prompt.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                if let toolCall = request.toolCall,
                   let rawInput = toolCall.rawInput?.value as? [String: Any],
                   let plan = PermissionRequestPromptExtractor.stringValue(rawInput["plan"]) {
                    PlanContentView(content: plan)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, minHeight: 200, maxHeight: 400, alignment: .leading)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                } else if let detail = prompt.detail {
                    Text(detail)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 6) {
                if let options = request.options {
                    ForEach(options, id: \.optionId) { option in
                        PermissionOptionButton(option: option, style: .inline) {
                            session.respondToPermission(optionId: option.optionId)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
