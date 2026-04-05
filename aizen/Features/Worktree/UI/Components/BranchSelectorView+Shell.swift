import SwiftUI

extension BranchSelectorView {
    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            listContent
        }
        .frame(width: 350, height: 400)
        .background(AppSurfaceTheme.backgroundColor())
        .onAppear {
            loadBranches()
        }
    }

    var header: some View {
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
    }
}
