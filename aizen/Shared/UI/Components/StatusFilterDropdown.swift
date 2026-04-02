//
//  StatusFilterDropdown.swift
//  aizen
//

import SwiftUI

struct StatusFilterDropdown: View {
    @Binding var selectedStatuses: Set<ItemStatus>

    private var isFiltering: Bool {
        !selectedStatuses.isEmpty && selectedStatuses.count < ItemStatus.allCases.count
    }

    var body: some View {
        Menu {
            Button {
                selectedStatuses = Set(ItemStatus.allCases)
            } label: {
                Label("filter.all", systemImage: "checkmark.circle")
            }

            Divider()

            ForEach(ItemStatus.allCases) { status in
                Button {
                    toggleStatus(status)
                } label: {
                    HStack {
                        Circle()
                            .fill(status.color)
                            .frame(width: 8, height: 8)
                        Text(status.title)
                        Spacer()
                        if selectedStatuses.contains(status) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            Divider()

            Button {
                selectedStatuses.removeAll()
            } label: {
                Label("filter.clear", systemImage: "xmark.circle")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isFiltering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                if isFiltering {
                    PillBadge(
                        text: "\(selectedStatuses.count)",
                        color: .secondary,
                        textColor: .secondary,
                        font: .caption2,
                        horizontalPadding: 4,
                        verticalPadding: 1,
                        backgroundOpacity: 0.25
                    )
                }
            }
            .foregroundStyle(isFiltering ? Color.accentColor : Color.secondary)
        }
        .menuStyle(.borderlessButton)
    }

    private func toggleStatus(_ status: ItemStatus) {
        if selectedStatuses.contains(status) {
            selectedStatuses.remove(status)
        } else {
            selectedStatuses.insert(status)
        }
    }
}

#Preview {
    StatusFilterDropdown(selectedStatuses: .constant(Set([.active, .paused])))
        .padding()
}
