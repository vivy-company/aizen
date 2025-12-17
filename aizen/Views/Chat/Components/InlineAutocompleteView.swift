//
//  InlineAutocompleteView.swift
//  aizen
//
//  SwiftUI popup content for inline autocomplete
//

import SwiftUI

struct InlineAutocompleteView: View {
    let items: [AutocompleteItem]
    let selectedIndex: Int
    let trigger: AutocompleteTrigger?
    let onTap: (AutocompleteItem) -> Void
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let trigger = trigger {
                AutocompleteHeader(trigger: trigger)
            }

            if items.isEmpty {
                emptyStateView
            } else {
                AutocompleteListView(
                    items: items,
                    selectedIndex: selectedIndex,
                    onTap: { item in
                        onTap(item)
                    }
                )
            }
        }
        .frame(width: 350)
        .fixedSize(horizontal: false, vertical: true)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.separator.opacity(0.3), lineWidth: 0.5)
        }
    }

    private var emptyStateView: some View {
        HStack {
            Text("No matches found")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}

// Separate view for the list with proper scroll handling
private struct AutocompleteListView: View {
    let items: [AutocompleteItem]
    let selectedIndex: Int
    let onTap: (AutocompleteItem) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        AutocompleteRow(
                            item: item,
                            isSelected: index == selectedIndex
                        )
                        .id(item.id)
                        .onTapGesture {
                            onTap(item)
                        }
                    }
                }
            }
            .frame(maxHeight: 250)
            .scrollDisabled(items.count <= 5)
            .onAppear {
                // Scroll to selected item when view appears
                if selectedIndex >= 0 && selectedIndex < items.count {
                    proxy.scrollTo(items[selectedIndex].id, anchor: nil)
                }
            }
        }
    }
}

// MARK: - Header

private struct AutocompleteHeader: View {
    let trigger: AutocompleteTrigger

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: iconName)
                    .font(.system(size: 10, weight: .medium))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text(hint)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()
        }
    }

    private var iconName: String {
        switch trigger {
        case .file: return "doc.text"
        case .command: return "command"
        }
    }

    private var title: String {
        switch trigger {
        case .file: return "Files"
        case .command: return "Commands"
        }
    }

    private var hint: String {
        "↑↓ navigate • ↵ select • esc dismiss"
    }
}

// MARK: - Row

private struct AutocompleteRow: View {
    let item: AutocompleteItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            itemIcon
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var itemIcon: some View {
        switch item {
        case .file(let result):
            FileIconView(path: result.path, size: 16)
        case .command:
            Image(systemName: "command")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}
