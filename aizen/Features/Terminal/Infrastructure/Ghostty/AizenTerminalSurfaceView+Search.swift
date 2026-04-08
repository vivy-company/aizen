import Foundation

@MainActor
extension AizenTerminalSurfaceView {
    func startSearch(_ startSearch: Ghostty.Action.StartSearch) {
        if let searchState {
            searchState.needle = startSearch.needle ?? ""
        } else {
            searchState = SearchState(needle: startSearch.needle ?? "")
            NotificationCenter.default.post(name: .ghosttySearchFocus, object: self)
        }
    }

    func updateSearchTotal(_ total: Int) {
        searchState?.total = total >= 0 ? UInt(total) : nil
    }

    func updateSearchSelected(_ selected: Int) {
        searchState?.selected = selected >= 0 ? UInt(selected) : nil
    }

    func endSearchFromGhostty() {
        searchState = nil
    }
}
