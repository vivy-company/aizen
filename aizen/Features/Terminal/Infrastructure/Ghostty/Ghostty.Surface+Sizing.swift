import GhosttyKit

extension Ghostty.Surface {
    struct TerminalSize {
        let columns: UInt16
        let rows: UInt16
        let widthPx: UInt32
        let heightPx: UInt32
        let cellWidthPx: UInt32
        let cellHeightPx: UInt32
    }

    @MainActor
    func terminalSize() -> TerminalSize {
        let cSize = ghostty_surface_size(unsafeCValue)
        return TerminalSize(
            columns: cSize.columns,
            rows: cSize.rows,
            widthPx: cSize.width_px,
            heightPx: cSize.height_px,
            cellWidthPx: cSize.cell_width_px,
            cellHeightPx: cSize.cell_height_px
        )
    }
}
