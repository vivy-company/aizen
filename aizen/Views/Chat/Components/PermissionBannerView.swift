//
//  PermissionBannerView.swift
//  aizen
//
//  Glass toast notification for pending permission requests with inline actions.
//

import ACP
import CoreData
import SwiftUI

struct PermissionBannerView: View {
    let currentChatSessionId: UUID?
    let onNavigate: (UUID) -> Void

    @ObservedObject private var chatSessionManager = ChatSessionManager.shared
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme

    private var pendingSessionInfo: PendingPermissionInfo? {
        for sessionId in chatSessionManager.sessionsWithPendingPermissions {
            if sessionId != currentChatSessionId {
                return fetchSessionInfo(for: sessionId)
            }
        }
        return nil
    }

    private func fetchSessionInfo(for chatSessionId: UUID) -> PendingPermissionInfo? {
        guard let agentSession = ChatSessionManager.shared.getAgentSession(for: chatSessionId),
              let request = agentSession.permissionHandler.permissionRequest else {
            return nil
        }

        let request2: NSFetchRequest<ChatSession> = ChatSession.fetchRequest()
        request2.predicate = NSPredicate(format: "id == %@", chatSessionId as CVarArg)
        request2.fetchLimit = 1

        var worktreeName = "Chat"
        if let session = try? viewContext.fetch(request2).first,
           let worktree = session.worktree {
            worktreeName = worktree.branch ?? "Chat"
        }

        return PendingPermissionInfo(
            sessionId: chatSessionId,
            worktreeName: worktreeName,
            message: request.message,
            options: request.options ?? [],
            handler: agentSession.permissionHandler
        )
    }

    var body: some View {
        if let info = pendingSessionInfo {
            bannerContent(info: info)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: info.sessionId)
                .padding(.top, 12)
        }
    }

    @ViewBuilder
    private func bannerContent(info: PendingPermissionInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top row - clickable to navigate
            Button {
                onNavigate(info.sessionId)
            } label: {
                HStack(spacing: 10) {
                    // Pulsing indicator
                    Circle()
                        .fill(.orange)
                        .frame(width: 8, height: 8)
                        .overlay {
                            Circle()
                                .stroke(.orange.opacity(0.5), lineWidth: 2)
                                .scaleEffect(1.5)
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("permission.banner.title \(info.worktreeName)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)

                        if let message = info.message, !message.isEmpty {
                            Text(message)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            // Bottom row - action buttons
            HStack(spacing: 8) {
                ForEach(info.options, id: \.optionId) { option in
                    PermissionOptionButton(option: option, style: .banner) {
                        info.handler.respondToPermission(optionId: option.optionId)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: 420)
        .background { glassBackground }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(strokeColor, lineWidth: 1)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.15), radius: 20, y: 8)
    }

    @ViewBuilder
    private var glassBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        if #available(macOS 26.0, *) {
            ZStack {
                GlassEffectContainer {
                    shape
                        .fill(.white.opacity(0.001))
                        .glassEffect(.regular.tint(tintColor), in: shape)
                }
                .allowsHitTesting(false)

                shape
                    .fill(scrimColor)
                    .allowsHitTesting(false)
            }
        } else {
            shape.fill(.ultraThinMaterial)
        }
    }

    private var tintColor: Color {
        colorScheme == .dark ? .black.opacity(0.22) : .white.opacity(0.6)
    }

    private var strokeColor: Color {
        colorScheme == .dark ? .white.opacity(0.14) : .black.opacity(0.08)
    }

    private var scrimColor: Color {
        colorScheme == .dark ? .black.opacity(0.12) : .white.opacity(0.06)
    }
}

// MARK: - Helper Types

private struct PendingPermissionInfo {
    let sessionId: UUID
    let worktreeName: String
    let message: String?
    let options: [PermissionOption]
    let handler: AgentPermissionHandler
}
