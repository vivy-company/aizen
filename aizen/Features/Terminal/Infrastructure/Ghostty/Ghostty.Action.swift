//
//  Ghostty.Action.swift
//  aizen
//
//  Action types for Ghostty terminal events
//

import Foundation
import GhosttyKit
import SwiftUI

// MARK: - Ghostty.Action

extension Ghostty {
    enum Action {}
    enum Notification {}
}

// MARK: - Scrollbar

extension Ghostty.Action {
    struct ColorChange {
        let kind: Kind
        let color: Color

        enum Kind {
            case foreground
            case background
            case cursor
            case palette(index: UInt8)
        }

        init(c: ghostty_action_color_change_s) {
            switch c.kind {
            case GHOSTTY_ACTION_COLOR_KIND_FOREGROUND:
                self.kind = .foreground
            case GHOSTTY_ACTION_COLOR_KIND_BACKGROUND:
                self.kind = .background
            case GHOSTTY_ACTION_COLOR_KIND_CURSOR:
                self.kind = .cursor
            default:
                self.kind = .palette(index: UInt8(c.kind.rawValue))
            }

            self.color = Color(
                red: Double(c.r) / 255,
                green: Double(c.g) / 255,
                blue: Double(c.b) / 255
            )
        }
    }

    struct ProgressReport {
        enum State {
            case remove
            case set
            case error
            case indeterminate
            case pause

            init(_ c: ghostty_action_progress_report_state_e) {
                switch c {
                case GHOSTTY_PROGRESS_STATE_REMOVE:
                    self = .remove
                case GHOSTTY_PROGRESS_STATE_SET:
                    self = .set
                case GHOSTTY_PROGRESS_STATE_ERROR:
                    self = .error
                case GHOSTTY_PROGRESS_STATE_INDETERMINATE:
                    self = .indeterminate
                case GHOSTTY_PROGRESS_STATE_PAUSE:
                    self = .pause
                default:
                    self = .remove
                }
            }
        }

        let state: State
        let progress: UInt8?
    }

    /// Represents the scrollbar state from the terminal core.
    ///
    /// ## Fields
    /// - `total`: Total rows in scrollback + active area
    /// - `offset`: First visible row (0 = top of history)
    /// - `len`: Number of visible rows (viewport height)
    struct Scrollbar {
        let total: UInt64
        let offset: UInt64
        let len: UInt64

        init(c: ghostty_action_scrollbar_s) {
            total = c.total
            offset = c.offset
            len = c.len
        }

        init(total: UInt64, offset: UInt64, len: UInt64) {
            self.total = total
            self.offset = offset
            self.len = len
        }
    }
}

// MARK: - Search

extension Ghostty.Action {
    struct StartSearch {
        let needle: String?

        init(c: ghostty_action_start_search_s) {
            if let needleCString = c.needle {
                needle = String(cString: needleCString)
            } else {
                needle = nil
            }
        }
    }

    enum KeyTable {
        case activate(name: String)
        case deactivate
        case deactivateAll

        init?(c: ghostty_action_key_table_s) {
            switch c.tag {
            case GHOSTTY_KEY_TABLE_ACTIVATE:
                let data = Data(bytes: c.value.activate.name, count: c.value.activate.len)
                let name = String(data: data, encoding: .utf8) ?? ""
                self = .activate(name: name)
            case GHOSTTY_KEY_TABLE_DEACTIVATE:
                self = .deactivate
            case GHOSTTY_KEY_TABLE_DEACTIVATE_ALL:
                self = .deactivateAll
            default:
                return nil
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when the terminal scrollbar state changes.
    /// userInfo contains ScrollbarKey with Ghostty.Action.Scrollbar value.
    static let ghosttyDidUpdateScrollbar = Notification.Name("win.aizen.app.ghostty.didUpdateScrollbar")

    /// Posted when a Ghostty terminal search overlay should move keyboard focus to its field.
    static let ghosttySearchFocus = Notification.Name("win.aizen.app.ghostty.searchFocus")

    static let ghosttyConfigDidChange = Notification.Name("win.aizen.app.ghostty.configDidChange")
    static let ghosttyColorDidChange = Notification.Name("win.aizen.app.ghostty.colorDidChange")
    static let ghosttyBellDidRing = Notification.Name("win.aizen.app.ghostty.bellDidRing")
    static let ghosttyDidChangeReadonly = Notification.Name("win.aizen.app.ghostty.readonlyDidChange")

    /// Key for scrollbar state in notification userInfo
    static let ScrollbarKey = ghosttyDidUpdateScrollbar.rawValue + ".scrollbar"
    static let GhosttyConfigChangeKey = ghosttyConfigDidChange.rawValue
    static let GhosttyColorChangeKey = ghosttyColorDidChange.rawValue
    static let ReadonlyKey = ghosttyDidChangeReadonly.rawValue + ".readonly"
}

extension Ghostty {
    static let userNotificationCategory = "win.aizen.app.userNotification"
}

extension Ghostty.Notification {
    static let didUpdateRendererHealth = Notification.Name("win.aizen.app.ghostty.didUpdateRendererHealth")
    static let didContinueKeySequence = Notification.Name("win.aizen.app.ghostty.didContinueKeySequence")
    static let didEndKeySequence = Notification.Name("win.aizen.app.ghostty.didEndKeySequence")
    static let KeySequenceKey = didContinueKeySequence.rawValue + ".key"
    static let didChangeKeyTable = Notification.Name("win.aizen.app.ghostty.didChangeKeyTable")
    static let KeyTableKey = didChangeKeyTable.rawValue + ".action"
}
