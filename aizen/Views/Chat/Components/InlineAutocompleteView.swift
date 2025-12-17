//
//  InlineAutocompleteView.swift
//  aizen
//
//  SwiftUI popup content for inline autocomplete
//

import SwiftUI

struct InlineAutocompleteView: View {
    @ObservedObject var handler: UnifiedAutocompleteHandler
    let onSelect: (AutocompleteItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let trigger = handler.state.trigger {
                AutocompleteHeader(trigger: trigger)
            }

            if handler.state.items.isEmpty {
                emptyStateView
            } else {
                itemsList
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

    private var itemsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(handler.state.items.enumerated()), id: \.element.id) { index, item in
                        AutocompleteRow(
                            item: item,
                            isSelected: index == handler.state.selectedIndex
                        )
                        .id(item.id)
                        .onTapGesture {
                            handler.state.selectedIndex = index
                            onSelect(item)
                        }
                    }
                }
            }
            .frame(maxHeight: 250)
            .onChange(of: handler.state.selectedIndex) { newIndex in
                if newIndex >= 0, newIndex < handler.state.items.count {
                    let item = handler.state.items[newIndex]
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(item.id, anchor: .center)
                    }
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
