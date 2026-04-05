//
//  WorktreeDetailsTab.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 04.11.25.
//

import SwiftUI
import os.log

struct DetailsTabView: View {
    @ObservedObject var worktree: Worktree
    @ObservedObject var repositoryManager: WorkspaceRepositoryStore
    var onWorktreeDeleted: ((Worktree?) -> Void)?

    let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "DetailsTabView")
    @State var currentBranch = ""
    @State var ahead = 0
    @State var behind = 0
    @State var isLoading = false
    @State var showingDeleteConfirmation = false
    @State var hasUnsavedChanges = false
    @State var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: worktree.isPrimary ? "arrow.triangle.branch" : "arrow.triangle.2.circlepath")
                        .font(.system(size: 48))
                        .foregroundStyle(.blue)

                    Text(worktree.branch ?? "Unknown")
                        .font(.title)
                        .fontWeight(.bold)

                    if worktree.isPrimary {
                        PillBadge(
                            text: String(localized: "worktree.detail.primary"),
                            color: .blue,
                            textColor: .white,
                            font: .caption,
                            fontWeight: .semibold,
                            horizontalPadding: 12,
                            verticalPadding: 4,
                            backgroundOpacity: 1.0
                        )
                    }
                }
                .padding(.top, 32)

                // Branch status
                if isLoading {
                    ProgressView()
                        .controlSize(.large)
                } else {
                    VStack(spacing: 12) {
                        if ahead > 0 || behind > 0 {
                            HStack(spacing: 20) {
                                if ahead > 0 {
                                    Label {
                                        Text(String(localized: "worktree.detail.ahead \(ahead)"))
                                    } icon: {
                                        Image(systemName: "arrow.up.circle.fill")
                                            .foregroundStyle(.green)
                                    }
                                }

                                if behind > 0 {
                                    Label {
                                        Text(String(localized: "worktree.detail.behind \(behind)"))
                                    } icon: {
                                        Image(systemName: "arrow.down.circle.fill")
                                            .foregroundStyle(.orange)
                                    }
                                }
                            }
                            .font(.callout)
                        } else {
                            Label(String(localized: "worktree.detail.upToDate"), systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }

                // Info section
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        InfoRow(label: String(localized: "worktree.detail.path"), value: worktree.path ?? String(localized: "worktree.list.unknown"))
                        Divider()
                        InfoRow(label: String(localized: "worktree.detail.branch"), value: currentBranch.isEmpty ? (worktree.branch ?? String(localized: "worktree.list.unknown")) : currentBranch)

                        if let lastAccessed = worktree.lastAccessed {
                            Divider()
                            InfoRow(label: String(localized: "worktree.detail.lastAccessed"), value: lastAccessed.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                    .padding(4)
                }
                .padding(.horizontal)

                // Actions
                VStack(spacing: 12) {
                    Text("worktree.detail.actions", bundle: .main)
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)

                    VStack(spacing: 8) {
                        ActionButton(
                            title: String(localized: "worktree.detail.openTerminal"),
                            icon: "terminal",
                            color: .blue
                        ) {
                            openInTerminal()
                        }

                        ActionButton(
                            title: String(localized: "worktree.detail.openFinder"),
                            icon: "folder",
                            color: .orange
                        ) {
                            openInFinder()
                        }

                        ActionButton(
                            title: String(localized: "worktree.detail.openEditor"),
                            icon: "chevron.left.forwardslash.chevron.right",
                            color: .purple
                        ) {
                            openInEditor()
                        }

                        if !worktree.isPrimary {
                            ActionButton(
                                title: String(localized: "worktree.detail.delete"),
                                icon: "trash",
                                color: .red
                            ) {
                                checkUnsavedChanges()
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal)
                }

                Spacer()
            }
        }
        .navigationTitle(String(localized: "worktree.list.title"))
        .toolbar {
            Button {
                refreshStatus()
            } label: {
                Label(String(localized: "worktree.detail.refresh"), systemImage: "arrow.clockwise")
            }
        }
        .task {
            refreshStatus()
        }
        .alert(hasUnsavedChanges ? String(localized: "worktree.detail.unsavedChangesTitle") : String(localized: "worktree.detail.deleteConfirmTitle"), isPresented: $showingDeleteConfirmation) {
            Button(String(localized: "worktree.create.cancel"), role: .cancel) {}
            Button(String(localized: "worktree.detail.delete"), role: .destructive) {
                deleteWorktree()
            }
        } message: {
            if hasUnsavedChanges {
                Text(String(localized: "worktree.detail.unsavedChangesMessage \(worktree.branch ?? String(localized: "worktree.list.unknown"))"))
            } else {
                Text("worktree.detail.deleteConfirmMessage", bundle: .main)
            }
        }
    }
}
