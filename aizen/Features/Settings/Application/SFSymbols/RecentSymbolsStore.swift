//
//  RecentSymbolsStore.swift
//  aizen
//

import Combine
import Foundation

final class RecentSymbolsStore: ObservableObject {
    static let shared = RecentSymbolsStore()

    private let key = "recentSFSymbols"
    private let maxRecent = 24

    @Published private(set) var recentSymbols: [String] = []

    private init() {
        loadRecent()
    }

    private func loadRecent() {
        recentSymbols = UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    func addRecent(_ symbol: String) {
        var recent = recentSymbols
        recent.removeAll { $0 == symbol }
        recent.insert(symbol, at: 0)
        if recent.count > maxRecent {
            recent = Array(recent.prefix(maxRecent))
        }
        recentSymbols = recent
        UserDefaults.standard.set(recent, forKey: key)
    }
}
