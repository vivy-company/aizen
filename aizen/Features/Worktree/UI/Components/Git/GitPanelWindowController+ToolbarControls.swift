//
//  GitPanelWindowController+ToolbarControls.swift
//  aizen
//
//  Branch and git action toolbar controls for the git panel window content.
//

import SwiftUI

extension GitPanelWindowContentWithToolbar {
    var branchSelector: some View {
        Button {
            showingBranchPicker = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                Text(gitStatus.currentBranch.isEmpty ? "HEAD" : gitStatus.currentBranch)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.bordered)
    }

    var gitActionsToolbar: some View {
        HStack(spacing: 4) {
            if let operation = currentOperation {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(operation.rawValue)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            } else if gitStatus.aheadCount > 0 && gitStatus.behindCount > 0 {
                Button {
                    performOperation(.pull) { gitOperations.pull() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down")
                        Text("Pull (\(gitStatus.behindCount))")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isOperationPending)

                Button {
                    performOperation(.push) { gitOperations.push() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up")
                        Text("Push (\(gitStatus.aheadCount))")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isOperationPending)
            } else if gitStatus.aheadCount > 0 {
                Button {
                    performOperation(.push) { gitOperations.push() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up")
                        Text("Push (\(gitStatus.aheadCount))")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isOperationPending)
            } else {
                Button {
                    performOperation(.fetch) { gitOperations.fetch() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Fetch")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isOperationPending)
            }

            if currentOperation == nil {
                Menu {
                    Button {
                        performOperation(.fetch) { gitOperations.fetch() }
                    } label: {
                        Label("Fetch", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(isOperationPending)

                    Button {
                        performOperation(.pull) { gitOperations.pull() }
                    } label: {
                        Label("Pull", systemImage: "arrow.down")
                    }
                    .disabled(isOperationPending)

                    Button {
                        performOperation(.push) { gitOperations.push() }
                    } label: {
                        Label("Push", systemImage: "arrow.up")
                    }
                    .disabled(isOperationPending)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .menuIndicator(.hidden)
                .buttonStyle(.bordered)
                .disabled(isOperationPending)
            }
        }
        .task(id: gitOperationService.isOperationPending) {
            guard !gitOperationService.isOperationPending else { return }
            currentOperation = nil
        }
    }

    func performOperation(_ operation: GitToolbarOperation, action: () -> Void) {
        currentOperation = operation
        action()
    }
}
