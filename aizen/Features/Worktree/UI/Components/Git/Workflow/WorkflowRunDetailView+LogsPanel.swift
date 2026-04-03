//
//  WorkflowRunDetailView+LogsPanel.swift
//  aizen
//
//  Logs panel rendering for workflow run details.
//

import SwiftUI

extension WorkflowRunDetailView {
    var isStatusMessage: Bool {
        let logs = service.runLogs
        return logs.contains("Waiting for job") ||
               logs.contains("Job is running") ||
               logs.contains("Workflow is running") ||
               logs.contains("Cancelling workflow") ||
               logs.contains("Workflow run cancelled") ||
               logs.contains("Failed to cancel") ||
               logs.contains("Failed to load logs") ||
               logs.contains("No logs available") ||
               logs.contains("Error fetching logs")
    }

    var statusMessageIcon: String {
        let logs = service.runLogs
        if logs.contains("cancelled") || logs.contains("Cancelling") {
            return "stop.circle"
        } else if logs.contains("Failed") || logs.contains("Error") {
            return "exclamationmark.triangle"
        } else if logs.contains("Waiting") {
            return "clock"
        } else if logs.contains("No logs available") {
            return "doc.text"
        }
        return "hourglass"
    }

    var logsPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Logs")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                if let job = jobs.first(where: { $0.id == selectedJobId }) {
                    Text("- \(job.name)")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                if run?.isInProgress == true {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Running")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !service.runLogs.isEmpty {
                    CopyButton(text: service.runLogs, iconSize: 12)
                        .help("Copy all logs")
                }

                if service.isLoadingLogs {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button {
                        Task {
                            await service.refreshLogs()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh logs")
                }
            }
            .frame(height: 32)
            .padding(.horizontal, 12)

            GitWindowDivider()

            if service.isLoadingLogs && service.runLogs.isEmpty {
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading logs...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if service.runLogs.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 30))
                        .foregroundStyle(.tertiary)
                    Text("Select a job to view logs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if isStatusMessage {
                VStack(spacing: 12) {
                    if run?.isInProgress == true {
                        ProgressView()
                            .controlSize(.regular)
                    } else {
                        Image(systemName: statusMessageIcon)
                            .font(.system(size: 32))
                            .foregroundStyle(.tertiary)
                    }
                    Text(service.runLogs)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding()
            } else {
                WorkflowLogView(service.runLogs, structuredLogs: service.structuredLogs, fontSize: 11, provider: service.provider)
            }
        }
    }
}
