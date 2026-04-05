import SwiftUI

extension BranchSelectorView {
    @ViewBuilder
    var listContent: some View {
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

                if allowCreation && !searchText.isEmpty {
                    Button {
                        createBranch()
                    } label: {
                        Label(String(localized: "git.branch.create \(searchText)"), systemImage: "plus.circle")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
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

    func branchRow(_ branch: BranchInfo) -> some View {
        Button {
            selectedBranch = branch
            onSelectBranch?(branch)
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
}
