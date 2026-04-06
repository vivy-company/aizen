//
//  GitPanelWindowController+PRButton.swift
//  aizen
//

import AppKit
import SwiftUI

extension GitPanelWindowContentWithToolbar {
    @ViewBuilder
    var prActionButton: some View {
        if let info = hostingInfo, info.provider != .unknown, !isOnMainBranch {
            if prOperationInProgress {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(info.provider == .gitlab ? "MR..." : "PR...")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            } else {
                switch prStatus {
                case .unknown, .noPR:
                    Button {
                        createPR()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.pull")
                            Text(info.provider == .gitlab ? "Create MR" : "Create PR")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isOperationPending || gitStatus.currentBranch.isEmpty)

                case .open(let number, let url, let mergeable, let title):
                    HStack(spacing: 4) {
                        Button {
                            if let prURL = URL(string: url) {
                                NSWorkspace.shared.open(prURL)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "number")
                                Text("\(number)")
                            }
                        }
                        .buttonStyle(.bordered)
                        .help(title)

                        Button {
                            mergePR(number: number)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.merge")
                                Text("Merge")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(!mergeable || isOperationPending)
                        .help(mergeable ? "Merge this PR" : "PR cannot be merged (conflicts or checks failing)")
                    }

                case .merged, .closed:
                    Button {
                        createPR()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.pull")
                            Text(info.provider == .gitlab ? "Create MR" : "Create PR")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isOperationPending || gitStatus.currentBranch.isEmpty)
                }
            }
        }
    }
}
