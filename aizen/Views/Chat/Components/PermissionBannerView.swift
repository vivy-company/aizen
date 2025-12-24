//
//  PermissionBannerView.swift
//  aizen
//
//  Floating banner shown when permission is pending in a different chat session.
//

import SwiftUI
import CoreData

struct PermissionBannerView: View {
    let currentChatSessionId: UUID?
    let onNavigate: (UUID) -> Void

    @ObservedObject private var chatSessionManager = ChatSessionManager.shared
    @Environment(\.managedObjectContext) private var viewContext

    private var pendingSessionInfo: (sessionId: UUID, worktreeName: String)? {
        // Find first pending permission that isn't the current session
        for sessionId in chatSessionManager.sessionsWithPendingPermissions {
            if sessionId != currentChatSessionId {
                // Look up worktree name
                let worktreeName = fetchWorktreeName(for: sessionId)
                return (sessionId, worktreeName)
            }
        }
        return nil
    }

    private func fetchWorktreeName(for chatSessionId: UUID) -> String {
        let request: NSFetchRequest<ChatSession> = ChatSession.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", chatSessionId as CVarArg)
        request.fetchLimit = 1

        do {
            if let session = try viewContext.fetch(request).first,
               let worktree = session.worktree {
                return worktree.branch ?? "Chat"
            }
        } catch {
            // Ignore fetch errors
        }
        return "Chat"
    }

    var body: some View {
        if let info = pendingSessionInfo {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(.orange)

                Text("permission.banner.message \(info.worktreeName)")
                    .font(.system(size: 12, weight: .medium))

                Spacer()

                Button {
                    onNavigate(info.sessionId)
                } label: {
                    Text("permission.banner.view")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .background(Color.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(response: 0.3), value: info.sessionId)
        }
    }
}
