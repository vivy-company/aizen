import AppKit
import GhosttyKit

extension Ghostty.Input {
    /// `ghostty_input_mouse_state_e`
    enum MouseState: String, CaseIterable {
        case release
        case press

        var cMouseState: ghostty_input_mouse_state_e {
            switch self {
            case .release: GHOSTTY_MOUSE_RELEASE
            case .press: GHOSTTY_MOUSE_PRESS
            }
        }
    }
}

extension Ghostty.Input {
    /// `ghostty_input_mouse_button_e`
    enum MouseButton: String, CaseIterable {
        case unknown
        case left
        case right
        case middle
        case four
        case five
        case six
        case seven
        case eight
        case nine
        case ten
        case eleven

        var cMouseButton: ghostty_input_mouse_button_e {
            switch self {
            case .unknown: GHOSTTY_MOUSE_UNKNOWN
            case .left: GHOSTTY_MOUSE_LEFT
            case .right: GHOSTTY_MOUSE_RIGHT
            case .middle: GHOSTTY_MOUSE_MIDDLE
            case .four: GHOSTTY_MOUSE_FOUR
            case .five: GHOSTTY_MOUSE_FIVE
            case .six: GHOSTTY_MOUSE_SIX
            case .seven: GHOSTTY_MOUSE_SEVEN
            case .eight: GHOSTTY_MOUSE_EIGHT
            case .nine: GHOSTTY_MOUSE_NINE
            case .ten: GHOSTTY_MOUSE_TEN
            case .eleven: GHOSTTY_MOUSE_ELEVEN
            }
        }

        init(fromNSEventButtonNumber buttonNumber: Int) {
            switch buttonNumber {
            case 0: self = .left
            case 1: self = .right
            case 2: self = .middle
            case 3: self = .eight
            case 4: self = .nine
            case 5: self = .six
            case 6: self = .seven
            case 7: self = .four
            case 8: self = .five
            case 9: self = .ten
            case 10: self = .eleven
            default: self = .unknown
            }
        }
    }
}

extension Ghostty.Input {
    /// `ghostty_input_mouse_momentum_e` - Momentum phase for scroll events
    enum Momentum: UInt8, CaseIterable {
        case none = 0
        case began = 1
        case stationary = 2
        case changed = 3
        case ended = 4
        case cancelled = 5
        case mayBegin = 6

        var cMomentum: ghostty_input_mouse_momentum_e {
            switch self {
            case .none: GHOSTTY_MOUSE_MOMENTUM_NONE
            case .began: GHOSTTY_MOUSE_MOMENTUM_BEGAN
            case .stationary: GHOSTTY_MOUSE_MOMENTUM_STATIONARY
            case .changed: GHOSTTY_MOUSE_MOMENTUM_CHANGED
            case .ended: GHOSTTY_MOUSE_MOMENTUM_ENDED
            case .cancelled: GHOSTTY_MOUSE_MOMENTUM_CANCELLED
            case .mayBegin: GHOSTTY_MOUSE_MOMENTUM_MAY_BEGIN
            }
        }
    }
}

extension Ghostty.Input.Momentum {
    init(_ phase: NSEvent.Phase) {
        switch phase {
        case .began: self = .began
        case .stationary: self = .stationary
        case .changed: self = .changed
        case .ended: self = .ended
        case .cancelled: self = .cancelled
        case .mayBegin: self = .mayBegin
        default: self = .none
        }
    }
}
