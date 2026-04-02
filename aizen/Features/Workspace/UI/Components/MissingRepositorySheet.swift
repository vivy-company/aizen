import SwiftUI
import UniformTypeIdentifiers

struct MissingRepositorySheet: View {
    let missing: WorkspaceRepositoryStore.MissingRepository
    @ObservedObject var repositoryManager: WorkspaceRepositoryStore
    @Binding var selectedRepository: Repository?
    @Binding var selectedWorktree: Worktree?
    let onDismiss: () -> Void

    @State private var showingFilePicker = false
    @State private var isRelocating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Project Not Found")
                .font(.headline)

            VStack(spacing: 8) {
                Text("The project \"\(missing.repository.name ?? "Unknown")\" could not be found at:")
                    .multilineTextAlignment(.center)

                Text(missing.lastKnownPath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(8)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))

                Text("It may have been moved or deleted.")
                    .foregroundStyle(.secondary)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 12) {
                Button(role: .destructive) {
                    removeRepository()
                } label: {
                    Text("Remove from Aizen")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    showingFilePicker = true
                } label: {
                    if isRelocating {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Locate Project...")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRelocating)
            }
        }
        .padding(24)
        .frame(width: 420)
        .settingsSheetChrome()
        .interactiveDismissDisabled()
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleRelocateResult(result)
        }
    }

    private func removeRepository() {
        do {
            if selectedRepository?.id == missing.repository.id {
                selectedRepository = nil
                selectedWorktree = nil
            }
            try repositoryManager.deleteRepository(missing.repository)
            onDismiss()
        } catch {
            errorMessage = "Failed to remove: \(error.localizedDescription)"
        }
    }

    private func handleRelocateResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            isRelocating = true
            errorMessage = nil

            Task {
                do {
                    try await repositoryManager.relocateRepository(missing.repository, to: url.path)
                    onDismiss()
                } catch {
                    isRelocating = false
                    errorMessage = "Invalid project: \(error.localizedDescription)"
                }
            }

        case .failure:
            break
        }
    }
}
