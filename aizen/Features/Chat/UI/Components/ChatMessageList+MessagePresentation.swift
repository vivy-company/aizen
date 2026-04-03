import AppKit
import SwiftUI
import VVChatTimeline

extension ChatMessageList {
    func userMessagePresentation(for message: MessageItem) -> VVChatMessagePresentation {
        VVChatMessagePresentation(
            timestampPrefixIconURL: timestampClockIconURL(),
            timestampSuffixIconURL: nil,
            timestampIconSize: timestampSymbolSize,
            timestampIconSpacing: 6
        )
    }

    var timestampSymbolSize: CGFloat {
        max(14, CGFloat(markdownFontSize) - 0.5)
    }

    func timestampClockIconURL() -> String? {
        symbolIconURL(
            "clock",
            fallbackID: "timestamp-clock",
            tintColor: timestampIconTintColor
        )
    }

    func copySuffixIconURL(for messageID: String) -> String? {
        let isActive = copiedUserMessageID == messageID
        let symbolName: String
        let tintColor: NSColor

        if isActive {
            switch copiedUserMessageState {
            case .idle:
                symbolName = "doc.on.doc"
                tintColor = copyIconIdleTintColor
            case .transition:
                symbolName = "ellipsis"
                tintColor = copyIconHoverTintColor
            case .confirmed:
                symbolName = "checkmark"
                tintColor = copyIconConfirmedTintColor
            }
        } else {
            symbolName = "doc.on.doc"
            tintColor = copyIconIdleTintColor
        }

        return symbolIconURL(
            symbolName,
            fallbackID: "copy-\(symbolName)-\(copyFooterStateToken(for: messageID))",
            tintColor: tintColor
        )
    }

    var timestampIconTintColor: NSColor {
        if colorScheme == .dark {
            return NSColor(calibratedWhite: 0.72, alpha: 1)
        }
        return NSColor(calibratedWhite: 0.42, alpha: 1)
    }

    var copyIconIdleTintColor: NSColor {
        if colorScheme == .dark {
            return NSColor(calibratedWhite: 0.66, alpha: 1)
        }
        return NSColor(calibratedWhite: 0.45, alpha: 1)
    }

    var copyIconHoverTintColor: NSColor {
        if colorScheme == .dark {
            return NSColor(calibratedRed: 0.84, green: 0.88, blue: 0.98, alpha: 1)
        }
        return NSColor(calibratedRed: 0.28, green: 0.38, blue: 0.58, alpha: 1)
    }

    var copyIconConfirmedTintColor: NSColor {
        if colorScheme == .dark {
            return NSColor(calibratedRed: 0.42, green: 0.82, blue: 0.56, alpha: 1)
        }
        return NSColor(calibratedRed: 0.14, green: 0.64, blue: 0.28, alpha: 1)
    }

    var dimmedMetaOpacity: Float {
        colorScheme == .dark ? 0.40 : 0.50
    }
}
