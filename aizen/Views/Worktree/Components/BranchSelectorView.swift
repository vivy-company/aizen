import SwiftUI

struct BranchSelectorView: View {
    let repository: Repository
    let repositoryManager: RepositoryManager
    @Binding var selectedBranch: BranchInfo?

    // Optional: Allow branch creation
    var allowCreation: Bool = false
    var onCreateBranch: ((String) -> Void)?

    @State private var searchText: String = ""
    @State private var branches: [BranchInfo] = []
    @State private var filteredBranches: [BranchInfo] = []
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?

    private let pageSize = 30
    @State private var displayedCount = 30

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header with search and close
            HStack(spacing: 12) {
                SearchField(
                    placeholder: allowCreation ? "git.branch.searchOrCreate" : "git.branch.search",
                    text: $searchText,
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

                DetailCloseButton(action: dismiss, size: 20)
                    .symbolRenderingMode(.hierarchical)
            }
            .padding(12)

            Divider()

            // Branch list
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.small)
                    Text(String(localized: "git.branch.loading"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 24))
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else if filteredBranches.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text(searchText.isEmpty ? String(localized: "git.branch.noBranches") : String(localized: "git.branch.noMatch \(searchText)"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        // Count label
                        HStack {
                            Text(String(localized: "git.branch.count \(filteredBranches.count)"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                        ForEach(Array(filteredBranches.prefix(displayedCount)), id: \.id) { branch in
                            branchRow(branch)
                        }

                        // Create branch option if no matches and creation allowed
                        if allowCreation && !searchText.isEmpty && filteredBranches.isEmpty {
                            Button {
                                createBranch()
                            } label: {
                                HStack {
                                    Image(systemName: "plus.circle")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.accentColor)

                                    Text(String(localized: "git.branch.create \(searchText)"))
                                        .font(.system(size: 12))
                                        .foregroundStyle(.primary)

                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                        }

                        // Load more row
                        if displayedCount < filteredBranches.count {
                            Button {
                                withAnimation {
                                    displayedCount = min(displayedCount + pageSize, filteredBranches.count)
                                }
                            } label: {
                                Text(String(localized: "git.branch.loadMore \(filteredBranches.count - displayedCount)"))
                                    .font(.caption)
                                    .foregroundStyle(Color.accentColor)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.bottom, 12)
                }
                .background(Color(nsColor: .controlBackgroundColor))
            }
        }
        .frame(width: 350, height: 400)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            loadBranches()
        }
        .onChange(of: searchText) { _ in
            filterBranches()
        }
    }

    private func branchRow(_ branch: BranchInfo) -> some View {
        Button {
            selectedBranch = branch
            if !allowCreation {
                dismiss()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 11))
                    .foregroundStyle(branch.id == selectedBranch?.id ? Color.accentColor : Color.secondary)

                Text(branch.name)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(branch.id == selectedBranch?.id ? .primary : .secondary)

                Spacer()

                if branch.id == selectedBranch?.id {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(branch.id == selectedBranch?.id ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(6)
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
    }

    private func createBranch() {
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
                    filterBranches()
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

    private func filterBranches() {
        if searchText.isEmpty {
            filteredBranches = branches
        } else {
            filteredBranches = branches.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
            }
        }
        // Reset pagination when filtering changes
        displayedCount = pageSize
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
        repositoryManager: RepositoryManager(viewContext: PersistenceController.preview.container.viewContext),
        selectedBranch: .constant(nil)
    )
}
