//
//  TerminalPaneView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import AppKit
import GhosttyKit
import SwiftUI

// MARK: - Voice Action

enum VoiceAction: Hashable {
    case toggle
    case cancel
    case accept
}

// MARK: - Terminal Pane View

struct TerminalPaneView: View {
    @ObservedObject var worktree: Worktree
    @ObservedObject var session: TerminalSession
    let paneId: String
    let effectiveThemeName: String
    let isSplit: Bool
    let isFocused: Bool
    let sessionManager: TerminalSessionManager
    @Binding var voiceAction: VoiceAction?
    let focusRequestVersion: Int
    let onFocus: () -> Void
    let onProcessExit: () -> Void
    let onTitleChange: (String) -> Void
    let onVoiceRecordingChanged: (Bool) -> Void

    @EnvironmentObject private var ghosttyApp: Ghostty.App

    @State private var surfaceView: AizenTerminalSurfaceView?
    @StateObject private var audioService = AudioService()
    @State private var showingVoiceRecording = false
    @State private var showingPermissionError = false
    @State private var permissionErrorMessage = ""
    @ObservedObject private var terminalTitleRegistry = TerminalTitleRegistry.shared

    @AppStorage("terminalNotificationsEnabled") private var notificationsEnabled = true
    @AppStorage("terminalProgressEnabled") private var progressEnabled = true
    @AppStorage("terminalVoiceButtonEnabled") private var voiceButtonEnabled = true

    private var surfaceAdapter: AizenTerminalSurfaceAdapter {
        AizenTerminalSurfaceAdapter(
            session: session,
            worktree: worktree,
            paneId: paneId,
            sessionManager: sessionManager,
            onProcessExit: {
                if notificationsEnabled && (!isFocused || !NSApp.isActive) {
                    TerminalNotificationManager.shared.notify(
                        title: "Terminal exited",
                        body: terminalTitleRegistry.title(for: session) ?? "Shell process ended"
                    )
                }
                onProcessExit()
            },
            onFocus: onFocus,
            onReady: { },
            onTitleChange: onTitleChange,
            onProgress: { _, _ in }
        )
    }

    var body: some View {
        Group {
            if let surfaceView {
                AizenInspectableSurface(
                    surfaceView: surfaceView,
                    adapter: surfaceAdapter,
                    effectiveThemeName: effectiveThemeName,
                    isSplit: isSplit,
                    isFocused: isFocused,
                    showsProgress: progressEnabled
                )
                .overlay(alignment: .bottom) {
                    if showingVoiceRecording {
                        voiceOverlay
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if !showingVoiceRecording && isFocused && voiceButtonEnabled {
                        voiceTriggerButton
                            .transition(.opacity)
                    }
                }
            } else {
                Color.clear
                    .onAppear {
                        resolveSurfaceIfNeeded()
                    }
            }
        }
        .onAppear {
            resolveSurfaceIfNeeded()
            surfaceView?.setGhosttyFocused(isFocused)
            if isFocused {
                requestSurfaceFocus()
            }
        }
        .task(id: isFocused) {
            surfaceView?.setGhosttyFocused(isFocused)
            if isFocused {
                requestSurfaceFocus()
            }
            if !isFocused, showingVoiceRecording {
                audioService.cancelRecording()
                setVoiceRecording(false)
            }
        }
        .task(id: focusRequestVersion) {
            if isFocused {
                requestSurfaceFocus()
            }
        }
        .onDisappear {
            if showingVoiceRecording {
                audioService.cancelRecording()
                setVoiceRecording(false)
            }
        }
        .task(id: voiceAction) {
            guard let action = voiceAction else { return }
            handleVoiceAction(action)
            voiceAction = nil
        }
        .alert("Voice Input Unavailable", isPresented: $showingPermissionError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(permissionErrorMessage)
        }
    }

    private func resolveSurfaceIfNeeded() {
        if let existing = surfaceView {
            surfaceAdapter.applyCallbacks(to: existing)
            existing.setGhosttyFocused(isFocused)
            return
        }

        if let sessionId = session.id,
           let existing = sessionManager.getTerminal(for: sessionId, paneId: paneId) {
            surfaceAdapter.applyCallbacks(to: existing)
            existing.setGhosttyFocused(isFocused)
            surfaceView = existing
            return
        }

        guard let app = ghosttyApp.app,
              let worktreePath = surfaceAdapter.worktreePath else {
            return
        }

        let created = AizenTerminalSurfaceView(
            frame: .zero,
            worktreePath: worktreePath,
            ghosttyApp: app,
            appWrapper: ghosttyApp,
            paneId: paneId,
            command: surfaceAdapter.initialCommand
        )
        surfaceAdapter.applyCallbacks(to: created)
        surfaceAdapter.store(surface: created)
        created.setGhosttyFocused(isFocused)
        surfaceView = created
    }

    private func requestSurfaceFocus() {
        resolveSurfaceIfNeeded()
        guard let surface = surfaceView else {
            return
        }

        // Already the first responder — skip the async dispatch to avoid
        // queueing a stale moveFocus that could race with a later click.
        guard surface.window?.firstResponder !== surface else { return }

        Ghostty.moveFocus(to: surface)
    }

    private var voiceOverlay: some View {
        VoiceRecordingView(
            audioService: audioService,
            onSend: { transcribedText in
                sendTranscriptionToTerminal(transcribedText)
                setVoiceRecording(false)
            },
            onCancel: {
                setVoiceRecording(false)
            }
        )
        .padding(12)
        .frame(maxWidth: 520)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .padding(16)
    }

    private var voiceTriggerButton: some View {
        Button {
            startVoiceRecording()
        } label: {
            Image(systemName: "mic.fill")
                .font(.system(size: 16, weight: .semibold))
                .padding(10)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .help("Voice input (⌘⇧M)")
        .padding(14)
    }

    private func handleVoiceAction(_ action: VoiceAction) {
        switch action {
        case .toggle:
            toggleVoiceRecording()
        case .cancel:
            audioService.cancelRecording()
            setVoiceRecording(false)
        case .accept:
            toggleVoiceRecording()
        }
    }

    private func toggleVoiceRecording() {
        if showingVoiceRecording {
            Task {
                let text = await audioService.stopRecording()
                await MainActor.run {
                    let fallback = text.isEmpty ? audioService.partialTranscription : text
                    sendTranscriptionToTerminal(fallback)
                    setVoiceRecording(false)
                }
            }
        } else {
            startVoiceRecording()
        }
    }

    private func startVoiceRecording() {
        Task {
            do {
                setVoiceRecording(true)
                try await audioService.startRecording()
            } catch {
                setVoiceRecording(false)
                if let recordingError = error as? AudioService.RecordingError {
                    permissionErrorMessage = recordingError.localizedDescription + "\n\nEnable Microphone and Speech Recognition in System Settings."
                } else {
                    permissionErrorMessage = error.localizedDescription
                }
                showingPermissionError = true
            }
        }
    }

    private func sendTranscriptionToTerminal(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        surfaceAdapter.sendText(trimmed)
    }

    private func setVoiceRecording(_ isRecording: Bool) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showingVoiceRecording = isRecording
        }
        onVoiceRecordingChanged(isRecording)
    }
}

private struct AizenInspectableSurface: View {
    @ObservedObject var surfaceView: AizenTerminalSurfaceView
    let adapter: AizenTerminalSurfaceAdapter
    let effectiveThemeName: String
    let isSplit: Bool
    let isFocused: Bool
    let showsProgress: Bool

    @FocusState private var surfaceFocus: Bool
    @State private var isHoveringURLLeft = false

    private var isFocusedSurface: Bool {
        surfaceFocus || isFocused
    }

    private var backgroundColor: Color {
        Color(nsColor: GhosttyThemeParser.loadBackgroundColor(named: effectiveThemeName))
    }

    var body: some View {
        ZStack {
            GeometryReader { geo in
                AizenTerminalSurfaceHost(
                    surfaceView: surfaceView,
                    adapter: adapter,
                    size: geo.size
                )
                .focused($surfaceFocus)

                if let surfaceSize = surfaceView.surfaceSize {
                    AizenSurfaceResizeOverlay(
                        geoSize: geo.size,
                        size: surfaceSize,
                        focusInstant: surfaceView.focusInstant
                    )
                }
            }

            if showsProgress,
               let progressReport = surfaceView.progressReport,
               progressReport.state != .remove {
                VStack(spacing: 0) {
                    AizenSurfaceProgressBar(report: progressReport)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
                .transition(.opacity)
            }

            if let url = surfaceView.hoverUrl {
                let padding: CGFloat = 5
                let cornerRadius: CGFloat = 9
                ZStack {
                    HStack {
                        Spacer()
                        VStack(alignment: .leading) {
                            Spacer()

                            Text(verbatim: url)
                                .padding(.init(top: padding, leading: padding, bottom: padding, trailing: padding))
                                .background(
                                    UnevenRoundedRectangle(cornerRadii: .init(topLeading: cornerRadius))
                                        .fill(.background)
                                )
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .opacity(isHoveringURLLeft ? 1 : 0)
                        }
                    }

                    HStack {
                        VStack(alignment: .leading) {
                            Spacer()

                            Text(verbatim: url)
                                .padding(.init(top: padding, leading: padding, bottom: padding, trailing: padding))
                                .background(
                                    UnevenRoundedRectangle(cornerRadii: .init(topTrailing: cornerRadius))
                                        .fill(.background)
                                )
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .opacity(isHoveringURLLeft ? 0 : 1)
                                .onHover { hovering in
                                    isHoveringURLLeft = hovering
                                }
                        }
                        Spacer()
                    }
                }
            }

            if let searchState = surfaceView.searchState {
                AizenSurfaceSearchOverlay(
                    surfaceView: surfaceView,
                    searchState: searchState,
                    onClose: {
                        Ghostty.moveFocus(to: surfaceView)
                        surfaceView.searchState = nil
                    }
                )
            }

            AizenBellBorderOverlay(bell: surfaceView.bell)
            AizenHighlightOverlay(highlighted: surfaceView.highlighted)

            if !surfaceView.healthy {
                Rectangle().fill(backgroundColor)
                AizenSurfaceMessageView(
                    title: "Renderer Failed",
                    message: "The terminal renderer exhausted GPU resources or failed to recover."
                )
            } else if surfaceView.error != nil {
                Rectangle().fill(backgroundColor)
                AizenSurfaceMessageView(
                    title: "Terminal Failed",
                    message: "The terminal failed to initialize. Check logs for the underlying error."
                )
            }

            if isSplit && !isFocusedSurface {
                Rectangle()
                    .fill(backgroundColor)
                    .allowsHitTesting(false)
                    .opacity(0.28)
            }
        }
    }
}

private struct AizenSurfaceResizeOverlay: View {
    let geoSize: CGSize
    let size: ghostty_surface_size_s
    let focusInstant: ContinuousClock.Instant?

    @State private var lastSize: CGSize?
    @State private var ready = false

    private let padding: CGFloat = 5
    private let durationMs: UInt64 = 500

    private var hidden: Bool {
        if !ready { return true }
        if lastSize == geoSize { return true }
        if let instant = focusInstant {
            let delta = instant.duration(to: ContinuousClock.now)
            if delta < .milliseconds(500) {
                DispatchQueue.main.async {
                    lastSize = geoSize
                }
                return true
            }
        }
        return false
    }

    var body: some View {
        Text(verbatim: "\(size.columns) ⨯ \(size.rows)")
            .padding(.init(top: padding, leading: padding, bottom: padding, trailing: padding))
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(.background)
                    .shadow(radius: 3)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .allowsHitTesting(false)
            .opacity(hidden ? 0 : 1)
            .task {
                try? await Task.sleep(for: .milliseconds(500))
                ready = true
            }
            .task(id: geoSize) {
                if ready {
                    try? await Task.sleep(for: .milliseconds(durationMs))
                }
                lastSize = geoSize
            }
    }
}

private struct AizenSurfaceSearchOverlay: View {
    let surfaceView: AizenTerminalSurfaceView
    @ObservedObject var searchState: SearchState
    let onClose: () -> Void

    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            searchField

            Button {
                navigateSearch("navigate_search:next")
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(AizenSearchButtonStyle())

            Button {
                navigateSearch("navigate_search:previous")
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(AizenSearchButtonStyle())

            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(AizenSearchButtonStyle())
        }
        .padding(8)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 4)
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .onAppear {
            isSearchFieldFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .ghosttySearchFocus)) { notification in
            guard notification.object as? AizenTerminalSurfaceView === surfaceView else { return }
            DispatchQueue.main.async {
                isSearchFieldFocused = true
            }
        }
    }

    private var searchField: some View {
        TextField("Search", text: $searchState.needle)
            .textFieldStyle(.plain)
            .frame(width: 180)
            .padding(.leading, 8)
            .padding(.trailing, 50)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.1))
            .cornerRadius(6)
            .focused($isSearchFieldFocused)
            .overlay(alignment: .trailing) {
                resultLabel
            }
            .onSubmit {
                navigateSearch("navigate_search:next")
            }
    }

    @ViewBuilder
    private var resultLabel: some View {
        if let selected = searchState.selected {
            Text("\(selected + 1)/\(searchState.total ?? 0)")
                .font(.caption)
                .foregroundColor(.secondary)
                .monospacedDigit()
                .padding(.trailing, 8)
        } else if let total = searchState.total {
            Text("-/\(total)")
                .font(.caption)
                .foregroundColor(.secondary)
                .monospacedDigit()
                .padding(.trailing, 8)
        }
    }

    private func navigateSearch(_ action: String) {
        guard let surface = surfaceView.surface else { return }
        ghostty_surface_binding_action(surface, action, UInt(action.lengthOfBytes(using: .utf8)))
    }
}

private struct AizenSearchButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isHovered || configuration.isPressed ? .primary : .secondary)
            .padding(.horizontal, 2)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .onHover { hovering in
                isHovered = hovering
            }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isPressed {
            return Color.primary.opacity(0.2)
        } else if isHovered {
            return Color.primary.opacity(0.1)
        } else {
            return Color.clear
        }
    }
}

private struct AizenSurfaceProgressBar: View {
    let report: Ghostty.Action.ProgressReport

    private var color: Color {
        switch report.state {
        case .error: return .red
        case .pause: return .orange
        default: return .accentColor
        }
    }

    private var progress: UInt8? {
        if let v = report.progress { return v }
        if report.state == .pause { return 100 }
        return nil
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                if let progress {
                    Rectangle()
                        .fill(color)
                        .frame(width: geometry.size.width * CGFloat(progress) / 100, height: geometry.size.height)
                        .animation(.easeInOut(duration: 0.2), value: progress)
                } else {
                    AizenBouncingProgressBar(color: color)
                }
            }
        }
        .frame(height: 2)
        .clipped()
        .allowsHitTesting(false)
    }
}

private struct AizenBouncingProgressBar: View {
    let color: Color
    @State private var position: CGFloat = 0

    private let barWidthRatio: CGFloat = 0.25

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(color.opacity(0.3))

                Rectangle()
                    .fill(color)
                    .frame(width: geometry.size.width * barWidthRatio, height: geometry.size.height)
                    .offset(x: position * (geometry.size.width * (1 - barWidthRatio)))
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                position = 1
            }
        }
        .onDisappear {
            position = 0
        }
    }
}

private struct AizenBellBorderOverlay: View {
    let bell: Bool

    var body: some View {
        Rectangle()
            .strokeBorder(
                Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.5),
                lineWidth: 3
            )
            .allowsHitTesting(false)
            .opacity(bell ? 1.0 : 0.0)
            .animation(.easeInOut(duration: 0.3), value: bell)
    }
}

private struct AizenHighlightOverlay: View {
    let highlighted: Bool

    @State private var borderPulse = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.accentColor.opacity(0.12),
                            Color.accentColor.opacity(0.03),
                            Color.clear
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: 2000
                    )
                )

            Rectangle()
                .strokeBorder(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.accentColor.opacity(0.8),
                            Color.accentColor.opacity(0.5),
                            Color.accentColor.opacity(0.8)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: borderPulse ? 4 : 2
                )
                .shadow(color: Color.accentColor.opacity(borderPulse ? 0.8 : 0.6), radius: borderPulse ? 12 : 8)
                .shadow(color: Color.accentColor.opacity(borderPulse ? 0.5 : 0.3), radius: borderPulse ? 24 : 16)
        }
        .allowsHitTesting(false)
        .opacity(highlighted ? 1.0 : 0.0)
        .animation(.easeOut(duration: 0.4), value: highlighted)
        .task(id: highlighted) {
            if highlighted {
                withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true)) {
                    borderPulse = true
                }
            } else {
                withAnimation(.easeOut(duration: 0.4)) {
                    borderPulse = false
                }
            }
        }
    }
}

private struct AizenSurfaceMessageView: View {
    let title: String
    let message: String

    var body: some View {
        HStack {
            Image("AppIconImage")
                .resizable()
                .scaledToFit()
                .frame(width: 128, height: 128)

            VStack(alignment: .leading) {
                Text(title)
                    .font(.title)
                Text(message)
                    .frame(maxWidth: 350)
            }
        }
        .padding()
    }
}
