import SwiftUI

extension WorkspaceSidebarView {
    var sidebarShell: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("workspace.sidebar.title")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Spacer(minLength: 8)
                    repositoryControls
                }
                .padding(.horizontal, 12)

                workspacePicker
                    .padding(.horizontal, 12)
            }
            .padding(.top, 12)
            .padding(.bottom, 4)

            if repositoryFiltersVisible {
                repositoryFiltersInline
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .padding(.bottom, 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if repositorySearchVisible {
                repositorySearchInline
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .padding(.bottom, 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            repositoriesContent
        }
    }
}
