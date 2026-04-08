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

    var emptyStateView: some View {
        HStack {
            Text("No matches found")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}
