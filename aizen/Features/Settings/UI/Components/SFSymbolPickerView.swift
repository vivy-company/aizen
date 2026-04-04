//
//  SFSymbolPickerView.swift
//  aizen
//
//  SF Symbol picker with full system symbols from CoreGlyphs bundle
//

import SwiftUI
import Combine

// MARK: - SFSymbolPickerView

struct SFSymbolPickerView: View {
    @Binding var selectedSymbol: String
    @Binding var isPresented: Bool
    @Environment(\.colorScheme) private var colorScheme

    @State var searchText = ""
    @State var selectedCategory = "all"
    @State var displayLimit = 200
    @StateObject var recentManager = RecentSymbolsStore.shared

    let provider = SFSymbolsProvider.shared
    let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 8)
    let pageSize = 200

    var surfaceColor: Color {
        AppSurfaceTheme.backgroundColor(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            categoryTabsView
            Divider()
            symbolGridView
        }
        .frame(width: 540, height: 480)
        .settingsSheetChrome()
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 12) {
            SearchField(
                placeholder: "Search symbols...",
                text: searchTextBinding,
                iconColor: .secondary,
                trailing: { EmptyView() }
            )
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            Button("Done") {
                isPresented = false
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
    }

    // MARK: - Category Tabs

    private var categoryTabsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                if !recentManager.recentSymbols.isEmpty && searchText.isEmpty {
                    categoryTab(key: "recent", icon: "clock", name: "Recent")
                }

                ForEach(provider.categories, id: \.key) { category in
                    categoryTab(key: category.key, icon: category.icon, name: category.name)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    private func categoryTab(key: String, icon: String, name: String) -> some View {
        Button {
            selectCategory(key)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(name)
                    .font(.system(size: 11, weight: selectedCategory == key ? .semibold : .regular))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                selectedCategory == key ?
                Color.accentColor.opacity(0.15) :
                Color.clear
            )
            .foregroundColor(selectedCategory == key ? .accentColor : .secondary)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private var searchTextBinding: Binding<String> {
        Binding(
            get: { searchText },
            set: { newValue in
                searchText = newValue
                displayLimit = pageSize
            }
        )
    }

    private func selectCategory(_ category: String) {
        selectedCategory = category
        displayLimit = pageSize
    }
}
