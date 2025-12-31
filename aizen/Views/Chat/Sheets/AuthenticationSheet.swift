//
//  AuthenticationSheet.swift
//  aizen
//
//  Authentication dialog for agent sessions
//

import SwiftUI
import os.log

struct AuthenticationSheet: View {
    private let logger = Logger.chat
    @ObservedObject var session: AgentSession
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMethodId: String?
    @State private var isAuthenticating = false

    var body: some View {
        VStack(spacing: 0) {
            DetailHeaderBar(
                showsBackground: false,
                padding: EdgeInsets(top: 20, leading: 24, bottom: 20, trailing: 24)
            ) {
                Text("chat.authentication.required", bundle: .main)
                    .font(.title2)
                    .fontWeight(.semibold)
            } trailing: {
                DetailCloseButton { dismiss() }
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !session.authMethods.isEmpty {
                        ForEach(session.authMethods, id: \.id) { method in
                            authMethodButton(for: method)
                        }
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "lock.shield")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)

                            Text("chat.authentication.needed", bundle: .main)
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Text("chat.authentication.instructions", bundle: .main)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                }
                .padding(24)
            }

            Divider()

            HStack(spacing: 12) {
                if isAuthenticating {
                    ProgressView()
                        .scaleEffect(0.8)
                        .controlSize(.small)
                    Text("chat.authentication.authenticating", bundle: .main)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(String(localized: "chat.authentication.skip")) {
                    Task {
                        isAuthenticating = true
                        do {
                            try await session.createSessionWithoutAuth()
                            await MainActor.run {
                                isAuthenticating = false
                                dismiss()
                            }
                        } catch {
                            await MainActor.run {
                                isAuthenticating = false
                                logger.error("Skip auth failed: \(error.localizedDescription)")
                            }
                        }
                    }
                }
                .buttonStyle(.borderless)
                .disabled(isAuthenticating)

                Button(String(localized: "chat.button.cancel")) {
                    dismiss()
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 500, height: 400)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func authMethodButton(for method: AuthMethod) -> some View {
        Button {
            selectedMethodId = method.id
            performAuthentication(methodId: method.id)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: selectedMethodId == method.id ? "checkmark.circle.fill" : "key.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(selectedMethodId == method.id ? .green : .blue)

                    Text(method.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: "arrow.right")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                if let description = method.description {
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if method.id == "claude-login" {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("chat.authentication.notImplemented", bundle: .main)
                            .font(.caption)
                            .foregroundStyle(.orange)

                        Text("chat.authentication.terminalInstructions", bundle: .main)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Text("claude /login")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))

                            Button {
                                Clipboard.copy("claude /login")
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }

                        Text("chat.authentication.skipInstructions", bundle: .main)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(16)
            .background(.quaternary.opacity(selectedMethodId == method.id ? 0.8 : 0.3), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(selectedMethodId == method.id ? Color.blue : Color.clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .disabled(isAuthenticating)
    }

    private func performAuthentication(methodId: String) {
        isAuthenticating = true

        Task {
            do {
                try await session.authenticate(authMethodId: methodId)
                await MainActor.run {
                    isAuthenticating = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isAuthenticating = false
                    logger.error("Authentication failed: \(error.localizedDescription)")
                }
            }
        }
    }
}
