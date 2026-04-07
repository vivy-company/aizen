import AppKit
import Foundation
import GhosttyKit
import OSLog

extension Ghostty.App {
    static func handleAction(_ app: ghostty_app_t, target: ghostty_target_s, action: ghostty_action_s) -> Bool {
        let terminalView: AizenTerminalSurfaceView? = {
            guard target.tag == GHOSTTY_TARGET_SURFACE else { return nil }
            let surface = target.target.surface
            guard let userdata = ghostty_surface_userdata(surface) else { return nil }
            return Unmanaged<AizenTerminalSurfaceView>.fromOpaque(userdata).takeUnretainedValue()
        }()

        switch action.tag {
        case GHOSTTY_ACTION_TOGGLE_VISIBILITY,
             GHOSTTY_ACTION_TOGGLE_QUICK_TERMINAL,
             GHOSTTY_ACTION_TOGGLE_COMMAND_PALETTE,
             GHOSTTY_ACTION_NEW_WINDOW,
             GHOSTTY_ACTION_NEW_TAB,
             GHOSTTY_ACTION_CLOSE_TAB,
             GHOSTTY_ACTION_CLOSE_WINDOW,
             GHOSTTY_ACTION_CLOSE_ALL_WINDOWS,
             GHOSTTY_ACTION_TOGGLE_FULLSCREEN,
             GHOSTTY_ACTION_TOGGLE_MAXIMIZE,
             GHOSTTY_ACTION_PRESENT_TERMINAL:
            Ghostty.logger.notice("Ignoring embedded Ghostty window action: \(String(describing: action.tag))")
            return true

        case GHOSTTY_ACTION_SET_TITLE:
            if let titlePtr = action.action.set_title.title {
                let title = String(cString: titlePtr)
                DispatchQueue.main.async {
                    terminalView?.onTitleChange?(title)
                }
            }
            return true

        case GHOSTTY_ACTION_PWD:
            return true

        case GHOSTTY_ACTION_PROMPT_TITLE:
            return true

        case GHOSTTY_ACTION_PROGRESS_REPORT:
            let report = action.action.progress_report
            let state = GhosttyProgressState(cState: report.state)
            let value = report.progress >= 0 ? Int(report.progress) : nil
            DispatchQueue.main.async {
                terminalView?.onProgressReport?(state, value)
            }
            return true

        case GHOSTTY_ACTION_CELL_SIZE:
            let cellSize = action.action.cell_size
            let backingSize = NSSize(width: Double(cellSize.width), height: Double(cellSize.height))
            DispatchQueue.main.async {
                guard let terminalView else { return }
                terminalView.cellSize = terminalView.convertFromBacking(backingSize)
            }
            return true

        case GHOSTTY_ACTION_SCROLLBAR:
            let scrollbar = Ghostty.Action.Scrollbar(c: action.action.scrollbar)
            NotificationCenter.default.post(
                name: .ghosttyDidUpdateScrollbar,
                object: terminalView,
                userInfo: [Foundation.Notification.Name.ScrollbarKey: scrollbar]
            )
            return true

        case GHOSTTY_ACTION_START_SEARCH:
            let startSearch = Ghostty.Action.StartSearch(c: action.action.start_search)
            DispatchQueue.main.async {
                terminalView?.startSearch(startSearch)
            }
            return true

        case GHOSTTY_ACTION_END_SEARCH:
            DispatchQueue.main.async {
                terminalView?.endSearchFromGhostty()
            }
            return true

        case GHOSTTY_ACTION_SEARCH_TOTAL:
            let total = action.action.search_total.total
            DispatchQueue.main.async {
                terminalView?.updateSearchTotal(total)
            }
            return true

        case GHOSTTY_ACTION_SEARCH_SELECTED:
            let selected = action.action.search_selected.selected
            DispatchQueue.main.async {
                terminalView?.updateSearchSelected(selected)
            }
            return true

        default:
            return false
        }
    }
}
