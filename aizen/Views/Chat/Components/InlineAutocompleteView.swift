//
//  InlineAutocompleteView.swift
//  aizen
//
//  SwiftUI popup content for inline autocomplete
//

import SwiftUI

struct InlineAutocompletePopupView: View {
    @ObservedObject var model: AutocompletePopupModel

    var body: some View {
        InlineAutocompleteView(
            items: model.items,
            selectedIndex: model.selectedIndex,
            trigger: model.trigger,
            itemsVersion: model.itemsVersion,
            onTap: { item in
                model.onTap?(item)
            },
            onSelect: {
                model.onSelect?()
            }
        )
    }
}

struct InlineAutocompleteView: View {
    let items: [AutocompleteItem]
    let selectedIndex: Int
    let trigger: AutocompleteTrigger?
    let itemsVersion: Int
    let onTap: (AutocompleteItem) -> Void
    let onSelect: () -> Void

    var body: some View {
        LiquidGlassCard(
            cornerRadius: 16,
            shadowOpacity: 0.30,
            sheenOpacity: 0.55
        ) {
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
                        itemsVersion: itemsVersion,
                        onTap: { item in
                            onTap(item)
                        }
                    )
                }
            }
        }
        .frame(width: 360)
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
    let itemsVersion: Int
    let onTap: (AutocompleteItem) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Invisible anchor at top for scroll reset
                    Color.clear
                        .frame(height: 0)
                        .id("autocomplete-top")

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
            .frame(maxHeight: 240)
            .onChange(of: itemsVersion) { _ in
                // Scroll to top when items list changes (user typed new chars)
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo("autocomplete-top", anchor: .top)
                }
            }
            .onChange(of: selectedIndex) { newValue in
                guard newValue >= 0 && newValue < items.count else { return }
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo(items[newValue].id, anchor: .center)
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
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                HStack(spacing: 6) {
                    KeyCap(text: "↑")
                    KeyCap(text: "↓")
                    KeyCap(text: "↩")
                    KeyCap(text: "esc")
                }
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            Divider()
                .opacity(0.25)
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

}

// MARK: - Row

private struct AutocompleteRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    let item: AutocompleteItem
    let isSelected: Bool

    private var selectionFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06)
    }

    private var hoverFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.03)
    }

    private var selectionStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06)
    }

    private var backgroundFill: Color {
        if isSelected {
            return selectionFill
        } else if isHovered {
            return hoverFill
        }
        return Color.clear
    }

    var body: some View {
        let selectionShape = RoundedRectangle(cornerRadius: 10, style: .continuous)

        HStack(spacing: 10) {
            itemIcon
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.system(size: 13, weight: .semibold))
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
        .padding(.vertical, 9)
        .background(
            selectionShape
                .fill(backgroundFill)
                .overlay {
                    if isSelected {
                        selectionShape.strokeBorder(selectionStroke, lineWidth: 1)
                    }
                }
        )
        .overlay {
            if isSelected && colorScheme == .dark {
                LinearGradient(
                    colors: [
                        .white.opacity(0.12),
                        .clear,
                        .white.opacity(0.06),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .blendMode(.plusLighter)
                .clipShape(selectionShape)
                .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
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
