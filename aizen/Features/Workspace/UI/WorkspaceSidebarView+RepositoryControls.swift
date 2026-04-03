import CoreData
import SwiftUI
import UniformTypeIdentifiers
import os.log

extension WorkspaceSidebarView {
    var inlineSearchStroke: Color {
        Color.primary.opacity(0.08)
    }

    var repositorySearchVisible: Bool {
        showingRepositorySearch || !searchText.isEmpty
    }

    var isRepositoryFiltering: Bool {
        !selectedStatusFilters.isEmpty && selectedStatusFilters.count < ItemStatus.allCases.count
    }

    var repositoryFiltersVisible: Bool {
        showingRepositoryFilters
    }

    func updateRepositoryFilters(_ filters: Set<ItemStatus>) {
        storedStatusFilters = ItemStatus.encode(filters)
    }

    func toggleRepositoryStatus(_ status: ItemStatus) {
        var filters = selectedStatusFilters
        if filters.contains(status) {
            filters.remove(status)
        } else {
            filters.insert(status)
        }
        updateRepositoryFilters(filters)
    }

    @ViewBuilder
    var repositoryFiltersInline: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button {
                    updateRepositoryFilters(Set(ItemStatus.allCases))
                } label: {
                    Label("filter.all", systemImage: "checkmark.circle")
                        .font(.caption)
                }
                .buttonStyle(.plain)

                Button {
                    storedStatusFilters = ""
                } label: {
                    Label("filter.clear", systemImage: "xmark.circle")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(ItemStatus.allCases) { status in
                    Button {
                        toggleRepositoryStatus(status)
                    } label: {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(status.color)
                                .frame(width: 9, height: 9)
                            Text(status.title)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            if selectedStatusFilters.contains(status) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(selectedStatusFilters.contains(status) ? Color.primary.opacity(0.12) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(inlineSearchStroke, lineWidth: 0.8)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    var repositorySearchInline: some View {
        SearchField(
            placeholder: "workspace.search.placeholder",
            text: $searchText,
            spacing: 8,
            iconSize: 15,
            iconWeight: .regular,
            iconColor: .secondary,
            textFont: .system(size: 14, weight: .medium),
            clearButtonSize: 13,
            clearButtonWeight: .semibold,
            trailing: {
                EmptyView()
            }
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(inlineSearchStroke, lineWidth: 0.8)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    var repositoryControls: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showingRepositoryFilters.toggle()
                }
            } label: {
                Image(systemName: (repositoryFiltersVisible || isRepositoryFiltering)
                      ? "line.3.horizontal.decrease.circle.fill"
                      : "line.3.horizontal.decrease.circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle((repositoryFiltersVisible || isRepositoryFiltering) ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .help("Filter projects")

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    if repositorySearchVisible {
                        showingRepositorySearch = false
                        searchText = ""
                    } else {
                        showingRepositorySearch = true
                    }
                }
            } label: {
                Image(systemName: repositorySearchVisible ? "xmark.circle.fill" : "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(repositorySearchVisible ? "Hide search" : "Search projects")
        }
    }
}
