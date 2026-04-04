import CoreData
import SwiftUI

struct BrowserSessionTabsView: View {
    @ObservedObject var manager: BrowserSessionStore

    var body: some View {
        HStack(spacing: 0) {
            Button(action: selectPreviousTab) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11))
                    .frame(width: 32, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(manager.sessions.count <= 1)

            Button(action: selectNextTab) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .frame(width: 32, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(manager.sessions.count <= 1)

            Divider()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(manager.sessions, id: \.id) { session in
                        sessionTab(for: session)
                    }
                }
            }

            Divider()

            Button(action: {
                manager.createSession()
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 12))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(String(localized: "browser.tab.new"))
        }
        .frame(height: 36)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private func selectPreviousTab() {
        guard let currentId = manager.activeSessionId,
              let currentIndex = manager.sessions.firstIndex(where: { $0.id == currentId }),
              currentIndex > 0,
              let previousId = manager.sessions[currentIndex - 1].id else { return }
        manager.selectSession(previousId)
    }

    private func selectNextTab() {
        guard let currentId = manager.activeSessionId,
              let currentIndex = manager.sessions.firstIndex(where: { $0.id == currentId }),
              currentIndex < manager.sessions.count - 1,
              let nextId = manager.sessions[currentIndex + 1].id else { return }
        manager.selectSession(nextId)
    }

    @ViewBuilder
    private func sessionTab(for session: BrowserSession) -> some View {
        BrowserTab(
            session: session,
            isSelected: manager.activeSessionId == session.id,
            onSelect: {
                if let sessionId = session.id {
                    manager.selectSession(sessionId)
                }
            },
            onClose: {
                if let sessionId = session.id {
                    manager.closeSession(sessionId)
                }
            }
        )
        .contextMenu {
            if let sessionId = session.id {
                Button("Close Tab") {
                    manager.closeSession(sessionId)
                }

                Divider()

                Button("Close All to the Left") {
                    closeAllToLeft(of: sessionId)
                }
                .disabled(!canCloseToLeft(of: sessionId))

                Button("Close All to the Right") {
                    closeAllToRight(of: sessionId)
                }
                .disabled(!canCloseToRight(of: sessionId))

                Divider()

                Button("Close Other Tabs") {
                    closeOtherTabs(except: sessionId)
                }
                .disabled(manager.sessions.count <= 1)
            }
        }
    }

    private func canCloseToLeft(of sessionId: UUID) -> Bool {
        guard let index = manager.sessions.firstIndex(where: { $0.id == sessionId }) else { return false }
        return index > 0
    }

    private func canCloseToRight(of sessionId: UUID) -> Bool {
        guard let index = manager.sessions.firstIndex(where: { $0.id == sessionId }) else { return false }
        return index < manager.sessions.count - 1
    }

    private func closeAllToLeft(of sessionId: UUID) {
        guard let index = manager.sessions.firstIndex(where: { $0.id == sessionId }) else { return }

        for i in (0..<index).reversed() {
            if let id = manager.sessions[i].id {
                manager.closeSession(id)
            }
        }
    }

    private func closeAllToRight(of sessionId: UUID) {
        guard let index = manager.sessions.firstIndex(where: { $0.id == sessionId }) else { return }

        for i in ((index + 1)..<manager.sessions.count).reversed() {
            if let id = manager.sessions[i].id {
                manager.closeSession(id)
            }
        }
    }

    private func closeOtherTabs(except sessionId: UUID) {
        for session in manager.sessions {
            if let id = session.id, id != sessionId {
                manager.closeSession(id)
            }
        }
    }
}
