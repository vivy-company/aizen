//
//  SFSymbolsProvider.swift
//  aizen
//

import Foundation

final class SFSymbolsProvider {
    static let shared = SFSymbolsProvider()

    private(set) var allSymbols: [String] = []
    private(set) var categories: [(key: String, icon: String, name: String)] = []
    private(set) var symbolToCategories: [String: [String]] = [:]

    private let localizedSuffixes = [".ar", ".hi", ".he", ".ja", ".ko", ".th", ".zh", ".rtl"]

    private init() {
        loadSymbols()
    }

    private func loadSymbols() {
        guard let bundle = Bundle(path: "/System/Library/CoreServices/CoreGlyphs.bundle") else {
            loadFallbackSymbols()
            return
        }

        if let categoriesPath = bundle.path(forResource: "categories", ofType: "plist"),
           let categoriesData = FileManager.default.contents(atPath: categoriesPath),
           let categoriesList = try? PropertyListSerialization.propertyList(from: categoriesData, format: nil)
            as? [[String: String]] {
            categories = categoriesList.compactMap { dict in
                guard let key = dict["key"], let icon = dict["icon"] else { return nil }
                return (key: key, icon: icon, name: displayName(for: key))
            }
        }

        if let symbolCategoriesPath = bundle.path(forResource: "symbol_categories", ofType: "plist"),
           let symbolCategoriesData = FileManager.default.contents(atPath: symbolCategoriesPath),
           let symbolCategoriesDict = try? PropertyListSerialization.propertyList(from: symbolCategoriesData, format: nil)
            as? [String: [String]] {
            symbolToCategories = symbolCategoriesDict
            allSymbols = symbolCategoriesDict.keys
                .filter { symbol in
                    !localizedSuffixes.contains { symbol.hasSuffix($0) }
                }
                .sorted()
        }
    }

    private func loadFallbackSymbols() {
        allSymbols = [
            "brain.head.profile", "cpu", "terminal", "command", "gearshape",
            "bolt", "star", "sparkle", "wand.and.stars", "lightbulb",
            "flame", "cloud", "server.rack", "desktopcomputer", "laptopcomputer",
            "iphone", "atom", "swift", "curlybraces",
            "text.bubble", "message", "envelope", "paperplane", "arrow.up.circle",
            "checkmark.circle", "xmark.circle", "exclamationmark.triangle", "questionmark.circle",
            "person", "person.2", "person.3", "folder", "doc.text"
        ]
        categories = [(key: "all", icon: "square.grid.2x2", name: "All")]
    }

    private func displayName(for key: String) -> String {
        switch key {
        case "all": return "All"
        case "whatsnew": return "What's New"
        case "draw": return "Draw"
        case "variable": return "Variable"
        case "multicolor": return "Multicolor"
        case "communication": return "Communication"
        case "weather": return "Weather"
        case "maps": return "Maps"
        case "objectsandtools": return "Objects & Tools"
        case "devices": return "Devices"
        case "cameraandphotos": return "Camera & Photos"
        case "gaming": return "Gaming"
        case "connectivity": return "Connectivity"
        case "transportation": return "Transportation"
        case "automotive": return "Automotive"
        case "accessibility": return "Accessibility"
        case "privacyandsecurity": return "Privacy & Security"
        case "human": return "Human"
        case "home": return "Home"
        case "fitness": return "Fitness"
        case "nature": return "Nature"
        case "editing": return "Editing"
        case "textformatting": return "Text Formatting"
        case "media": return "Media"
        case "keyboard": return "Keyboard"
        case "commerce": return "Commerce"
        case "time": return "Time"
        case "health": return "Health"
        case "shapes": return "Shapes"
        case "arrows": return "Arrows"
        case "indices": return "Indices"
        case "math": return "Math"
        default: return key.capitalized
        }
    }

    func symbols(for category: String) -> [String] {
        if category == "all" {
            return allSymbols
        }

        return allSymbols.filter { symbol in
            symbolToCategories[symbol]?.contains(category) ?? false
        }
    }

    func search(_ query: String) -> [String] {
        let lowercasedQuery = query.lowercased()
        let queryWords = lowercasedQuery.split(separator: " ").map(String.init)

        return allSymbols.filter { symbol in
            let symbolLower = symbol.lowercased()
            return queryWords.allSatisfy { word in
                symbolLower.contains(word)
            }
        }
    }
}
