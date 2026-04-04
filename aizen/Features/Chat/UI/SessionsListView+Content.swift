//
//  SessionsListView+Content.swift
//  aizen
//

import SwiftUI

extension SessionsListView {
    var headerView: some View {
        HStack(spacing: 12) {
            Text("Sessions")
                .font(.headline)

            if !viewModel.sessions.isEmpty {
                TagBadge(text: "\(viewModel.sessions.count)", color: .secondary, cornerRadius: 6)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(surfaceColor)
    }

    var agentFilterMenu: some View {
        Menu {
            Button {
                viewModel.selectedAgentName = nil
            } label: {
                Label("All Agents", systemImage: "person.2")
            }

            if !viewModel.availableAgents.isEmpty {
                Divider()
            }

            ForEach(viewModel.availableAgents, id: \.self) { agentName in
                Button {
                    viewModel.selectedAgentName = agentName
                } label: {
                    HStack(spacing: 8) {
                        AgentIconView(agent: agentName, size: 14)
                        Text(agentName)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                if let selectedAgent = viewModel.selectedAgentName {
                    AgentIconView(agent: selectedAgent, size: 14)
                } else {
                    Image(systemName: "person.2")
                        .font(.system(size: 12))
                }

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(viewModel.availableAgents.isEmpty)
    }

    var contentView: some View {
        Group {
            if viewModel.isLoading && viewModel.sessions.isEmpty {
                loadingState
            } else if viewModel.sessions.isEmpty {
                emptyState
            } else {
                sessionsList
            }
        }
    }

    var loadingState: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
            Text("Loading sessions...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No Sessions")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Chat sessions will appear here")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var sessionsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.sessions, id: \.id) { session in
                    SessionRowView(session: session)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.resumeSession(session)
                            dismiss()
                        }
                        .onAppear {
                            viewModel.loadMoreIfNeeded(for: session)
                        }
                        .contextMenu {
                            sessionContextMenu(for: session)
                        }

                    Divider()
                }
            }
        }
    }

    @ViewBuilder
    func sessionContextMenu(for session: ChatSession) -> some View {
        Button {
            viewModel.resumeSession(session)
            dismiss()
        } label: {
            Label("Resume Session", systemImage: "play.fill")
        }

        Divider()

        if session.archived {
            Button {
                viewModel.unarchiveSession(session, context: viewContext)
            } label: {
                Label("Unarchive", systemImage: "tray.and.arrow.up")
            }
        } else {
            Button {
                viewModel.archiveSession(session, context: viewContext)
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
        }

        Divider()

        Button(role: .destructive) {
            viewModel.deleteSession(session, context: viewContext)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}
