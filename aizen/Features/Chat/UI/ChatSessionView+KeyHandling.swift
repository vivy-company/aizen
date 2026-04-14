import ACP
import AppKit
import CoreData
import SwiftUI
import VVChatTimeline

extension ChatSessionView {
    func startKeyMonitorIfNeeded() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleVoiceShortcut(event)
        }
    }

    func stopKeyMonitorIfNeeded() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    func handleVoiceShortcut(_ event: NSEvent) -> NSEvent? {
        guard isSelected else { return event }

        let keyCodeEscape: UInt16 = 53
        let keyCodeReturn: UInt16 = 36
        let keyCodeC: UInt16 = 8

        if event.keyCode == keyCodeEscape,
           shouldLetPresentedSheetHandleEscape(event) {
            return event
        }

        if event.keyCode == keyCodeEscape, let permissionRequest = currentPermissionRequest {
            handlePermissionPickerEscape(request: permissionRequest)
            return nil
        }

        if showingVoiceRecording {
            if event.keyCode == keyCodeEscape {
                cancelChatVoiceRecording()
                return nil
            }
            if event.keyCode == keyCodeReturn {
                acceptChatVoiceRecording()
                return nil
            }
        }

        if event.modifierFlags.contains(.control),
           event.keyCode == keyCodeC {
            if !inputText.isEmpty {
                inputText = ""
                return nil
            }
        }

        if event.keyCode == keyCodeEscape && !showingVoiceRecording {
            if viewModel.isProcessing {
                viewModel.cancelCurrentPrompt()
                return nil
            } else if !inputText.isEmpty {
                inputText = ""
                return nil
            }
        }

        if event.modifierFlags.contains(.command),
           event.modifierFlags.contains(.shift),
           event.charactersIgnoringModifiers?.lowercased() == "m" {
            toggleChatVoiceRecording()
            return nil
        }

        return event
    }

    func shouldLetPresentedSheetHandleEscape(_ event: NSEvent) -> Bool {
        guard let eventWindow = event.window else { return false }

        if eventWindow.sheetParent != nil {
            return true
        }

        return eventWindow.attachedSheet != nil
    }

    func handlePermissionPickerEscape(request: RequestPermissionRequest) {
        if viewModel.isProcessing {
            viewModel.cancelCurrentPrompt()
        }

        if let optionId = preferredPermissionDismissOptionId(for: request),
           let agentSession = viewModel.currentAgentSession {
            agentSession.respondToPermission(optionId: optionId)
        } else if let agentSession = viewModel.currentAgentSession {
            agentSession.permissionHandler.cancelPendingRequest()
        } else {
            viewModel.showingPermissionAlert = false
        }
    }

    func preferredPermissionDismissOptionId(for request: RequestPermissionRequest) -> String? {
        let options = request.options
        guard !options.isEmpty else {
            return nil
        }
        if let dismissOption = options.first(where: { isPermissionDismissOptionKind($0.kind) }) {
            return dismissOption.optionId
        }
        return options.last?.optionId
    }

    func isPermissionDismissOptionKind(_ kind: String) -> Bool {
        let normalized = kind.lowercased()
        return normalized.contains("reject")
            || normalized.contains("deny")
            || normalized.contains("cancel")
            || normalized.contains("decline")
    }
}
