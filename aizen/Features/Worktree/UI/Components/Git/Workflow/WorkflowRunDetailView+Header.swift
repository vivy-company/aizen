//
//  WorkflowRunDetailView+Header.swift
//  aizen
//
//  Header rendering for workflow run details.
//

import SwiftUI

extension WorkflowRunDetailView {
    func runHeader(_ run: WorkflowRun) -> some View {
        HStack(spacing: 12) {
            statusBadge(run)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(run.workflowName)
                        .font(.system(size: 13, weight: .semibold))

                    Text("#\(run.runNumber)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Label(run.branch, systemImage: "arrow.triangle.branch")
                    Label(run.commit, systemImage: "number")
                    Label(run.event, systemImage: "bolt")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }

            Spacer()

            if run.isInProgress {
                Button {
                    showCancelConfirmation = true
                } label: {
                    Label("Cancel", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.small)
                .confirmationDialog(
                    "Cancel Workflow Run?",
                    isPresented: $showCancelConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Cancel Run", role: .destructive) {
                        Task {
                            _ = await service.cancelRun(run)
                        }
                    }
                    Button("Keep Running", role: .cancel) {}
                } message: {
                    Text("This will stop the workflow run #\(run.runNumber). This action cannot be undone.")
                }
            }

            if let url = run.url, let urlObj = URL(string: url) {
                Link(destination: urlObj) {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.borderless)
                .help("Open in browser")
            }
        }
        .frame(height: 44)
        .padding(.horizontal, 12)
    }

    func statusBadge(_ run: WorkflowRun) -> some View {
        HStack(spacing: 4) {
            WorkflowRunStatusIconView(
                run: run,
                iconSize: 11,
                progressFrame: 12,
                progressStyle: .mini
            )

            Text(run.displayStatus)
                .font(.system(size: 11, weight: .semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .foregroundStyle(.white)
        .background(statusBackgroundColor(run))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    func statusBackgroundColor(_ run: WorkflowRun) -> Color {
        WorkflowStatusIcon.badgeBackgroundColor(status: run.status, conclusion: run.conclusion)
    }
}
