import SwiftUI

extension PullRequestDetailPane {
    @ViewBuilder
    var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                Task { await viewModel.checkoutBranch() }
            } label: {
                Label("Checkout", systemImage: "arrow.triangle.branch")
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isPerformingAction)

            Button {
                viewModel.openInBrowser()
            } label: {
                Label("Open", systemImage: "safari")
            }
            .buttonStyle(.bordered)

            Spacer()

            if pr.state == .open {
                Button {
                    Task { await viewModel.approve() }
                } label: {
                    Label("Approve", systemImage: "checkmark")
                }
                .buttonStyle(.bordered)
                .tint(.green)
                .disabled(!viewModel.canApprove || viewModel.isPerformingAction)

                Button {
                    showRequestChangesSheet = true
                } label: {
                    Label("Request Changes", systemImage: "xmark")
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .disabled(!viewModel.canApprove || viewModel.isPerformingAction)

                Menu {
                    ForEach(PRMergeMethod.allCases, id: \.self) { method in
                        Button(method.displayName) {
                            Task { await viewModel.merge(method: method) }
                        }
                    }
                } label: {
                    Label("Merge", systemImage: "arrow.triangle.merge")
                }
                .menuStyle(.borderedButton)
                .disabled(!viewModel.canMerge || viewModel.isPerformingAction)

                Button {
                    Task { await viewModel.close() }
                } label: {
                    Label("Close", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(!viewModel.canClose || viewModel.isPerformingAction)
            }

            if viewModel.isPerformingAction {
                ProgressView()
                    .scaleEffect(0.7)
            }
        }
        .padding(12)
    }

    @ViewBuilder
    var requestChangesSheet: some View {
        VStack(spacing: 16) {
            Text("Request Changes")
                .font(.headline)

            TextEditor(text: $requestChangesText)
                .font(.system(size: 13))
                .frame(minHeight: 100)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(GitWindowDividerStyle.color(opacity: 0.9), lineWidth: 1)
                )

            HStack {
                Button("Cancel") {
                    showRequestChangesSheet = false
                    requestChangesText = ""
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Submit") {
                    let text = requestChangesText
                    showRequestChangesSheet = false
                    requestChangesText = ""
                    Task { await viewModel.requestChanges(body: text) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(requestChangesText.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400, height: 250)
    }
}
