//
//  ChatSessionView+Lifecycle.swift
//  aizen
//
//  Lifecycle and side-effect handlers for the chat session screen.
//

import SwiftUI

extension ChatSessionView {
    func applyLifecycleModifiers<Content: View>(to content: Content) -> some View {
        content
            .onAppear {
                handleOnAppear()
            }
            .onDisappear {
                handleOnDisappear()
            }
            .task(id: isSelected) {
                await handleSelectionChange()
            }
            .task(id: inputText) {
                handleInputTextChange()
            }
            .onReceive(viewModel.autocompleteHandler.$state) { state in
                handleAutocompleteStateChange(state)
            }
    }

    func handleOnAppear() {
        if let draft = viewModel.loadDraftInputText() {
            inputText = draft
        }
    }

    func handleOnDisappear() {
        viewModel.persistDraftState(inputText: inputText)
        viewModel.cancelPendingAutoScroll()
        viewModel.scrollRequest = nil
        autocompleteWindow?.dismiss()
        NotificationCenter.default.post(name: .chatViewDidDisappear, object: nil)
        stopKeyMonitorIfNeeded()
        chatActions.clear()
        if showingVoiceRecording {
            viewModel.audioService.cancelRecording()
            showingVoiceRecording = false
        }
    }

    func handleSelectionChange() async {
        if isSelected {
            chatActions.configure(cycleModeForward: viewModel.cycleModeForward)
            viewModel.prepareAgentSession()
            viewModel.scheduleAgentSessionActivation()
            setupAutocompleteWindow()
            NotificationCenter.default.post(name: .chatViewDidAppear, object: nil)
            startKeyMonitorIfNeeded()
        } else {
            viewModel.cancelScheduledAgentSessionActivation()
            viewModel.cancelPendingAutoScroll()
            viewModel.scrollRequest = nil
            autocompleteWindow?.dismiss()
            NotificationCenter.default.post(name: .chatViewDidDisappear, object: nil)
            stopKeyMonitorIfNeeded()
            chatActions.clear()
            if showingVoiceRecording {
                viewModel.audioService.cancelRecording()
                showingVoiceRecording = false
            }
        }
    }

    func handleInputTextChange() {
        viewModel.debouncedPersistDraft(inputText: inputText)
    }

    func handleAutocompleteStateChange(_ state: AutocompleteState) {
        updateAutocompleteWindow(state: state)
    }
}
