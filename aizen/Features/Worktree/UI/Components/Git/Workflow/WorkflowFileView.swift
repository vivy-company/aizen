//
//  WorkflowFileView.swift
//  aizen
//
//  Displays workflow YAML file content in code editor
//

import SwiftUI

struct WorkflowFileView: View {
    let workflow: Workflow
    let worktreePath: String

    @State private var fileContent: String = ""
    @State private var isLoading: Bool = true
    @State private var error: String?

    @AppStorage("editorFontFamily") private var editorFontFamily: String = "Menlo"
    @AppStorage("editorFontSize") private var editorFontSize: Double = 12

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            GitWindowDivider()

            // Content
            if isLoading {
                loadingView
            } else if let error = error {
                errorView(error)
            } else {
                codeEditor
            }
        }
        .onAppear {
            loadFile()
        }
    }

    private func loadFile() {
        Task {
            isLoading = true
            error = nil
            fileContent = ""
            await loadWorkflowFile()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(workflow.state == .active ? Color.green : Color.gray)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(workflow.name)
                    .font(.system(size: 14, weight: .semibold))

                Text(workflow.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .frame(height: 44)
        .padding(.horizontal, 12)
    }

    // MARK: - Content Views

    private var codeEditor: some View {
        CodeEditorView(
            content: fileContent,
            language: "yaml",
            isEditable: true,
            filePath: "\(worktreePath)/\(workflow.path)",
            repoPath: worktreePath,
            onContentChange: { newContent in
                fileContent = newContent
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text("Loading workflow file...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(.yellow)

            Text("Failed to load workflow file")
                .font(.subheadline)
                .fontWeight(.medium)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - File Loading

    private func loadWorkflowFile() async {
        let filePath = "\(worktreePath)/\(workflow.path)"

        await Task.detached {
            do {
                let content = try String(contentsOfFile: filePath, encoding: .utf8)
                await MainActor.run {
                    fileContent = content
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isLoading = false
                }
            }
        }.value
    }
}
