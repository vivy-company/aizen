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

struct PlanApprovalPickerView: View {
    private enum Layout {
        static let cornerRadius: CGFloat = 22
        static let horizontalPadding: CGFloat = 14
        static let topPadding: CGFloat = 14
        static let bottomPadding: CGFloat = 12
    }

    @ObservedObject var session: ChatAgentSession
    let request: RequestPermissionRequest
    let onDismissWithoutResponse: () -> Void

    @State var selectedIndex = 0
    @State var keyMonitor: Any?

    var options: [PermissionOption] {
        request.options ?? []
    }

    private var prompt: PermissionRequestPrompt {
        request.promptDescription
    }

    private var optionIdentityKey: String {
        options.map(\.optionId).joined(separator: "|")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(prompt.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)

            if let detail = prompt.detail {
                Text(detail)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .top, spacing: 8) {
                VStack(spacing: 4) {
                    if options.isEmpty {
                        Text("No options available")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                            optionRow(option: option, index: index)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 4) {
                    pickerArrowButton(systemName: "arrow.up", action: { moveSelection(-1) })
                    pickerArrowButton(systemName: "arrow.down", action: { moveSelection(1) })
                }
                .padding(.top, 1)
                .opacity(options.count > 1 ? 1 : 0.45)
            }

            HStack(spacing: 8) {
                Spacer(minLength: 8)

                Button {
                    dismissRequest()
                } label: {
                    HStack(spacing: 8) {
                        Text("Dismiss")
                            .font(.system(size: 12, weight: .semibold))
                        Text("ESC")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.primary.opacity(0.08), in: Capsule())
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .keyboardShortcut(.escape, modifiers: [])

                Button {
                    submitSelectedOption()
                } label: {
                    HStack(spacing: 8) {
                        Text("Submit")
                        Text("ENTER")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.primary.opacity(0.08), in: Capsule())
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(canSubmit ? .white : .secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(canSubmit ? Color.accentColor : Color.secondary.opacity(0.18), in: Capsule())
                .disabled(!canSubmit)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.top, Layout.topPadding)
        .padding(.bottom, Layout.bottomPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { liquidGlassBackground }
        .onAppear {
            selectedIndex = min(selectedIndex, max(options.count - 1, 0))
            installKeyboardMonitorIfNeeded()
        }
        .task(id: optionIdentityKey) {
            selectedIndex = min(selectedIndex, max(options.count - 1, 0))
        }
        .onDisappear {
            removeKeyboardMonitor()
        }
    }

    var canSubmit: Bool {
        !options.isEmpty && selectedIndex >= 0 && selectedIndex < options.count
    }

    func submitSelectedOption() {
        guard canSubmit else { return }
        let option = options[selectedIndex]
        session.respondToPermission(optionId: option.optionId)
    }

    func submitOption(at index: Int) {
        guard index >= 0 && index < options.count else { return }
        selectedIndex = index
        session.respondToPermission(optionId: options[index].optionId)
    }

    func dismissRequest() {
        if let option = preferredDismissOption {
            session.respondToPermission(optionId: option.optionId)
        } else {
            // Avoid leaving the agent turn blocked if no options are provided.
            session.permissionHandler.cancelPendingRequest()
            onDismissWithoutResponse()
        }
    }

    var preferredDismissOption: PermissionOption? {
        options.first(where: { isDismissOption($0.kind) }) ?? options.last
    }

    func isDismissOption(_ kind: String) -> Bool {
        let normalized = kind.lowercased()
        return normalized.contains("reject")
            || normalized.contains("deny")
            || normalized.contains("cancel")
            || normalized.contains("decline")
    }

    func moveSelection(_ delta: Int) {
        guard options.count > 1 else { return }
        let next = max(0, min(selectedIndex + delta, options.count - 1))
        selectedIndex = next
    }

    func numberShortcut(for index: Int) -> KeyEquivalent {
        let number = min(max(index + 1, 1), 9)
        return KeyEquivalent(Character("\(number)"))
    }

}

struct PermissionRequestPrompt {
    let title: String
    let detail: String?
}
