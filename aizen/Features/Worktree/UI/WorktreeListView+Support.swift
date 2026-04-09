import SwiftUI

extension WorktreeListView {
    var repositoryWorktrees: [Worktree] {
        workspaceGraphQueryController.worktrees(in: repository)
    }

    var selectedStatusFilters: Set<ItemStatus> {
        ItemStatus.decode(storedStatusFilters)
    }

    var selectedStatusFiltersBinding: Binding<Set<ItemStatus>> {
        Binding(
            get: { ItemStatus.decode(storedStatusFilters) },
            set: { storedStatusFilters = ItemStatus.encode($0) }
        )
    }

    var sortedWorktrees: [Worktree] {
        repositoryWorktrees.sorted { wt1, wt2 in
            if wt1.isPrimary != wt2.isPrimary {
                return wt1.isPrimary
            }
            return (wt1.branch ?? "") < (wt2.branch ?? "")
        }
    }

    var worktrees: [Worktree] {
        var result = sortedWorktrees

        if !selectedStatusFilters.isEmpty && selectedStatusFilters.count < ItemStatus.allCases.count {
            result = result.filter { worktree in
                let status = ItemStatus(rawValue: worktree.status ?? "active") ?? .active
                return selectedStatusFilters.contains(status)
            }
        }

        if !searchText.isEmpty {
            result = result.filter { worktree in
                (worktree.branch ?? "").localizedCaseInsensitiveContains(searchText) ||
                (worktree.path ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }

        return result
    }

    var worktreeSessionCounts: [UUID: WorktreeSessionCounts] {
        Dictionary(
            uniqueKeysWithValues: worktrees.compactMap { worktree in
                guard let worktreeId = worktree.id else { return nil }
                return (worktreeId, WorktreeSessionSnapshotBuilder.counts(for: worktree))
            }
        )
    }

    var searchFieldStroke: Color {
        colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.06)
    }

    var searchFieldFillFallback: Color {
        colorScheme == .dark
            ? AppSurfaceTheme.backgroundColor().opacity(0.58)
            : AppSurfaceTheme.backgroundColor().opacity(0.78)
    }

    @ViewBuilder
    var searchFieldBackground: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer {
                Capsule()
                    .fill(.white.opacity(0.001))
                    .glassEffect(.regular, in: Capsule())
            }
            .allowsHitTesting(false)
        } else {
            Capsule()
                .fill(.ultraThinMaterial)
                .background(searchFieldFillFallback, in: Capsule())
        }
    }
}
