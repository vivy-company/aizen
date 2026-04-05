import SwiftUI

struct BranchSelectorView: View {
    let repository: Repository
    let repositoryManager: WorkspaceRepositoryStore
    @Binding var selectedBranch: BranchInfo?
    var onSelectBranch: ((BranchInfo) -> Void)? = nil

    // Optional: Allow branch creation
    var allowCreation: Bool = false
    var onCreateBranch: ((String) -> Void)?

    @State var searchText: String = ""
    @State var branches: [BranchInfo] = []
    @State var isLoading: Bool = true
    @State var errorMessage: String?

    let pageSize = 30
    @State var displayedCount = 30

    @Environment(\.dismiss) var dismiss

    var filteredBranches: [BranchInfo] {
        if searchText.isEmpty {
            return branches
        }
        return branches.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var searchBinding: Binding<String> {
        Binding(
            get: { searchText },
            set: { newValue in
                searchText = newValue
                displayedCount = pageSize
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with search and close
            HStack(spacing: 12) {
                SearchField(
                    placeholder: allowCreation ? "git.branch.searchOrCreate" : "git.branch.search",
                    text: searchBinding,
                    iconColor: .secondary,
                    onSubmit: {
                        if allowCreation && !searchText.isEmpty && filteredBranches.isEmpty {
                            createBranch()
                        }
                    },
                    trailing: { EmptyView() }
                )
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)

                DetailCloseButton(action: { dismiss() }, size: 20)
                    .symbolRenderingMode(.hierarchical)
            }
            .padding(12)

            Divider()

            listContent
        }
        .frame(width: 350, height: 400)
        .background(AppSurfaceTheme.backgroundColor())
        .onAppear {
            loadBranches()
        }
    }

    func createBranch() {
        guard !searchText.isEmpty else { return }
        onCreateBranch?(searchText)
        dismiss()
    }

    private func loadBranches() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let loadedBranches = try await repositoryManager.getBranches(for: repository)
                await MainActor.run {
                    branches = loadedBranches
                    displayedCount = pageSize
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = String(localized: "git.branch.loadFailed \(error.localizedDescription)")
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Compact Display Button

struct BranchSelectorButton: View {
    let selectedBranch: BranchInfo?
    let defaultBranch: String
    @Binding var isPresented: Bool

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Text(selectedBranch?.name ?? defaultBranch)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    BranchSelectorView(
        repository: Repository(),
        repositoryManager: WorkspaceRepositoryStore(viewContext: PersistenceController.preview.container.viewContext),
        selectedBranch: .constant(nil)
    )
}
