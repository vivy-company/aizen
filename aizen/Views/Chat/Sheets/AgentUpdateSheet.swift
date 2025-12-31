//
//  AgentUpdateSheet.swift
//  aizen
//
//  Sheet to prompt user to update outdated ACP agents
//

import SwiftUI

struct AgentUpdateSheet: View {
    let agentName: String
    let versionInfo: AgentVersionInfo
    @Environment(\.dismiss) private var dismiss
    @State private var isUpdating = false
    @State private var updateProgress = ""
    @State private var updateError: String?

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.blue)

                Text("Update Available")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("A newer version of \(agentName) is available")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Version info
            VStack(spacing: 12) {
                versionRow(label: "Current version:", value: versionInfo.current ?? "Unknown")
                versionRow(label: "Latest version:", value: versionInfo.latest ?? "Unknown", accent: true)
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)

            // Update progress
            if isUpdating {
                VStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(updateProgress)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }

            // Error message
            if let error = updateError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }

            // Actions
            HStack(spacing: 12) {
                Button("Later") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .disabled(isUpdating)

                Button("Update Now") {
                    performUpdate()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isUpdating)
            }
            .padding(.top, 8)
        }
        .padding(24)
        .frame(width: 400)
    }

    private func performUpdate() {
        isUpdating = true
        updateError = nil

        Task {
            do {
                try await AgentUpdater.shared.updateAgentWithProgress(
                    agentName: agentName
                ) { progress in
                    updateProgress = progress
                }

                // Success - wait a moment then dismiss
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isUpdating = false
                    updateError = error.localizedDescription
                }
            }
        }
    }

    private func versionRow(label: String, value: String, accent: Bool = false) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .foregroundColor(accent ? .blue : .primary)
        }
    }
}
