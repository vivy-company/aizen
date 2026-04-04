//
//  SFSymbolPickerView+Grid.swift
//  aizen
//

import SwiftUI

extension SFSymbolPickerView {
    var allFilteredSymbols: [String] {
        if !searchText.isEmpty {
            return provider.search(searchText)
        }
        if selectedCategory == "recent" {
            return recentManager.recentSymbols
        }
        return provider.symbols(for: selectedCategory)
    }

    var displayedSymbols: [String] {
        Array(allFilteredSymbols.prefix(displayLimit))
    }

    var hasMore: Bool {
        allFilteredSymbols.count > displayLimit
    }

    var symbolGridView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                HStack {
                    Text("\(allFilteredSymbols.count) symbols")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)

                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(displayedSymbols, id: \.self) { symbol in
                        symbolButton(symbol)
                    }
                }
                .padding(.horizontal, 12)

                if hasMore {
                    Button {
                        displayLimit += pageSize
                    } label: {
                        Text("Load more (\(allFilteredSymbols.count - displayLimit) remaining)")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 12)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    func symbolButton(_ symbol: String) -> some View {
        Button {
            selectedSymbol = symbol
            recentManager.addRecent(symbol)
            isPresented = false
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .frame(width: 56, height: 56)
                .foregroundColor(selectedSymbol == symbol ? .white : .primary)
                .background(selectedSymbol == symbol ? Color.accentColor : surfaceColor)
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .help(symbol)
    }
}
