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
    let session: AgentSession?
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

struct PlanApprovalPickerView: View {
    private enum Layout {
        static let cornerRadius: CGFloat = 22
        static let horizontalPadding: CGFloat = 14
        static let topPadding: CGFloat = 14
        static let bottomPadding: CGFloat = 12
    }

    @ObservedObject var session: AgentSession
    let request: RequestPermissionRequest
    let onDismissWithoutResponse: () -> Void

    @State private var selectedIndex = 0
    @State private var keyMonitor: Any?

    private var options: [PermissionOption] {
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
        .onChange(of: optionIdentityKey) { _, _ in
            selectedIndex = min(selectedIndex, max(options.count - 1, 0))
        }
        .onDisappear {
            removeKeyboardMonitor()
        }
    }

    @ViewBuilder
    private func optionRow(option: PermissionOption, index: Int) -> some View {
        let isSelected = index == selectedIndex
        Button {
            selectedIndex = index
            submitOption(at: index)
        } label: {
            HStack(spacing: 8) {
                Text("\(index + 1).")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .frame(width: 18, alignment: .trailing)

                Text(option.name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.55) : Color.clear,
                        lineWidth: isSelected ? 1 : 0
                    )
            }
        }
        .buttonStyle(.plain)
        .keyboardShortcut(numberShortcut(for: index), modifiers: [])
    }

    private func pickerArrowButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 28, height: 24)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(options.count <= 1)
        .keyboardShortcut(systemName == "arrow.up" ? .upArrow : .downArrow, modifiers: [])
    }

    private var canSubmit: Bool {
        !options.isEmpty && selectedIndex >= 0 && selectedIndex < options.count
    }

    private func submitSelectedOption() {
        guard canSubmit else { return }
        let option = options[selectedIndex]
        session.respondToPermission(optionId: option.optionId)
    }

    private func submitOption(at index: Int) {
        guard index >= 0 && index < options.count else { return }
        selectedIndex = index
        session.respondToPermission(optionId: options[index].optionId)
    }

    private func dismissRequest() {
        if let option = preferredDismissOption {
            session.respondToPermission(optionId: option.optionId)
        } else {
            // Avoid leaving the agent turn blocked if no options are provided.
            session.permissionHandler.cancelPendingRequest()
            onDismissWithoutResponse()
        }
    }

    private var preferredDismissOption: PermissionOption? {
        options.first(where: { isDismissOption($0.kind) }) ?? options.last
    }

    private func isDismissOption(_ kind: String) -> Bool {
        let normalized = kind.lowercased()
        return normalized.contains("reject")
            || normalized.contains("deny")
            || normalized.contains("cancel")
            || normalized.contains("decline")
    }

    private func moveSelection(_ delta: Int) {
        guard options.count > 1 else { return }
        let next = max(0, min(selectedIndex + delta, options.count - 1))
        selectedIndex = next
    }

    private func numberShortcut(for index: Int) -> KeyEquivalent {
        let number = min(max(index + 1, 1), 9)
        return KeyEquivalent(Character("\(number)"))
    }

    @ViewBuilder
    private var liquidGlassBackground: some View {
        let shape = RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            GlassEffectContainer {
                shape
                    .fill(.white.opacity(0.001))
                    .glassEffect(.regular, in: shape)
                shape
                    .fill(.white.opacity(0.035))
            }
        } else {
            shape.fill(.ultraThinMaterial)
        }
    }

    private func installKeyboardMonitorIfNeeded() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if handleKeyDown(event) {
                return nil
            }
            return event
        }
    }

    private func removeKeyboardMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 126: // Up arrow
            moveSelection(-1)
            return true
        case 125: // Down arrow
            moveSelection(1)
            return true
        case 36, 76: // Return / Enter
            submitSelectedOption()
            return true
        case 53: // Escape
            dismissRequest()
            return true
        default:
            if let index = numberKeyCodeToIndex[event.keyCode], index < options.count {
                submitOption(at: index)
                return true
            }
            break
        }

        return false
    }

    private var numberKeyCodeToIndex: [UInt16: Int] {
        // Top-row number key codes on macOS keyboard layout: 1...9
        [18: 0, 19: 1, 20: 2, 21: 3, 23: 4, 22: 5, 26: 6, 28: 7, 25: 8]
    }
}

struct PermissionRequestPrompt {
    let title: String
    let detail: String?
}

extension RequestPermissionRequest {
    var promptDescription: PermissionRequestPrompt {
        if let toolCall,
           let rawInput = toolCall.rawInput?.value as? [String: Any],
           let plan = PermissionRequestPromptExtractor.stringValue(rawInput["plan"]),
           !plan.isEmpty {
            let title = normalizedMessage ?? "Implement this plan?"
            return PermissionRequestPrompt(title: title, detail: plan)
        }

        if let command = promptCommand, !command.isEmpty {
            return PermissionRequestPrompt(
                title: "Allow this command to run?",
                detail: command
            )
        }

        if let filePath = promptFilePath, !filePath.isEmpty {
            return PermissionRequestPrompt(
                title: "Allow this file to be modified?",
                detail: filePath
            )
        }

        if let url = promptURL, !url.isEmpty {
            return PermissionRequestPrompt(
                title: "Allow this URL to be opened?",
                detail: url
            )
        }

        return PermissionRequestPrompt(
            title: normalizedMessage ?? "Choose an option",
            detail: nil
        )
    }

    private var normalizedMessage: String? {
        guard let normalized = message?.trimmingCharacters(in: .whitespacesAndNewlines),
              !normalized.isEmpty else {
            return nil
        }
        return normalized
    }

    private var promptCommand: String? {
        guard let toolCall,
              let rawInput = toolCall.rawInput?.value as? [String: Any] else {
            return nil
        }
        return PermissionRequestPromptExtractor.commandValue(
            in: rawInput,
            preferredKeys: ["command", "cmd", "shellCommand", "commandLine", "command_line", "args", "argv"]
        )
    }

    private var promptFilePath: String? {
        guard let toolCall,
              let rawInput = toolCall.rawInput?.value as? [String: Any] else {
            return nil
        }
        return PermissionRequestPromptExtractor.stringValue(
            in: rawInput,
            preferredKeys: ["file_path", "path", "filePath", "filepath", "file"]
        )
    }

    private var promptURL: String? {
        guard let toolCall,
              let rawInput = toolCall.rawInput?.value as? [String: Any] else {
            return nil
        }
        return PermissionRequestPromptExtractor.stringValue(
            in: rawInput,
            preferredKeys: ["url", "uri", "href"]
        )
    }
}

enum PermissionRequestPromptExtractor {
    static func stringValue(in dict: [String: Any], preferredKeys: [String]) -> String? {
        for key in preferredKeys {
            if let value = stringValue(dict[key]) {
                return value
            }
        }
        return nil
    }

    static func commandValue(in dict: [String: Any], preferredKeys: [String]) -> String? {
        for key in preferredKeys {
            if let value = commandValue(dict[key]) {
                return value
            }
        }
        return nil
    }

    static func stringValue(_ value: Any?, depth: Int = 0) -> String? {
        guard depth < 8, let value else { return nil }

        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        if let dict = value as? [String: Any] {
            for key in ["value", "text", "path", "file_path", "filePath", "filepath", "url", "uri", "href", "command"] {
                if let nested = stringValue(dict[key], depth: depth + 1) {
                    return nested
                }
            }
        }

        if let array = value as? [Any] {
            for item in array {
                if let nested = stringValue(item, depth: depth + 1) {
                    return nested
                }
            }
        }

        return nil
    }

    static func commandValue(_ value: Any?, depth: Int = 0) -> String? {
        guard depth < 8, let value else { return nil }

        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        if let strings = value as? [String] {
            let cleaned = strings
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return cleaned.isEmpty ? nil : cleaned.joined(separator: " ")
        }

        if let dict = value as? [String: Any] {
            for key in ["value", "text", "command", "cmd", "shellCommand", "commandLine", "command_line", "args", "argv"] {
                if let nested = commandValue(dict[key], depth: depth + 1) {
                    return nested
                }
            }
        }

        if let array = value as? [Any] {
            let strings = array.compactMap { item -> String? in
                guard let string = item as? String else { return nil }
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            if !strings.isEmpty {
                return strings.joined(separator: " ")
            }

            for item in array {
                if let nested = commandValue(item, depth: depth + 1) {
                    return nested
                }
            }
        }

        return nil
    }
}
