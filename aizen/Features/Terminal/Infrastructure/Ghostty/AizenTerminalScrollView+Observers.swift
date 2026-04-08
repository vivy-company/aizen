import AppKit
import Combine

extension AizenTerminalScrollView {
    func installObservers() {
        // We listen for scroll events through bounds notifications on our NSClipView.
        // This is based on: https://christiantietze.de/posts/2018/07/synchronize-nsscrollview/
        scrollView.contentView.postsBoundsChangedNotifications = true
        observers.append(NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] notification in
            self?.handleScrollChange(notification)
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: .ghosttyDidUpdateScrollbar,
            object: surfaceView,
            queue: .main
        ) { [weak self] notification in
            self?.handleScrollbarUpdate(notification)
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: NSScrollView.willStartLiveScrollNotification,
            object: scrollView,
            queue: .main
        ) { [weak self] _ in
            self?.isLiveScrolling = true
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: NSScrollView.didEndLiveScrollNotification,
            object: scrollView,
            queue: .main
        ) { [weak self] _ in
            self?.isLiveScrolling = false
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: NSScrollView.didLiveScrollNotification,
            object: scrollView,
            queue: .main
        ) { [weak self] _ in
            self?.handleLiveScroll()
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: NSScroller.preferredScrollerStyleDidChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.handleScrollerStyleChange()
        })

        if #unavailable(macOS 26.1) { if #available(macOS 26.0, *) {
            observers.append(NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: nil,
                queue: nil
            ) { [weak self] notification in
                self?.handleFrameChangeForNSScrollPocket(notification)
            })
        }}
    }

    func installSubscriptions() {
        surfaceView.$derivedConfig
            .sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    self?.handleConfigChange()
                }
            }
            .store(in: &cancellables)

        surfaceView.$pointerStyle
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newStyle in
                self?.scrollView.documentCursor = newStyle.cursor
            }
            .store(in: &cancellables)
    }
}
