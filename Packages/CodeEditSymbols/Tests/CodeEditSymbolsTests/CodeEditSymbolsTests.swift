import XCTest
import SwiftUI
import SnapshotTesting
@testable import CodeEditSymbols

final class CodeEditSymbolsTests: XCTestCase {

    // MARK: - NSImage Tests

    // MARK: VAULT

    private let record: Bool = false

    func testCreateNSImageVault() {
        let image = NSImage.vault
        let view = NSImageView(image: image)
        view.appearance = .init(named: .aqua)
        assertSnapshot(matching: view, as: .image, record: record)
    }

    func testCreateNSImageVaultFill() {
        let image = NSImage.vault_fill
        let view = NSImageView(image: image)
        view.appearance = .init(named: .aqua)
        assertSnapshot(matching: view, as: .image, record: record)
    }

    // MARK: COMMIT

    func testCreateNSImageCommit() {
        let image = NSImage.commit
        let view = NSImageView(image: image)
        view.appearance = .init(named: .aqua)
        assertSnapshot(matching: view, as: .image, record: record)
    }

    // MARK: CHECKOUT

    func testCreateNSImageCheckout() {
        let image = NSImage.checkout
        let view = NSImageView(image: image)
        view.appearance = .init(named: .aqua)
        assertSnapshot(matching: view, as: .image, record: record)
    }

    // MARK: BRANCH

    func testCreateNSImageBranch() {
        let image = NSImage.branch
        let view = NSImageView(image: image)
        view.appearance = .init(named: .aqua)
        assertSnapshot(matching: view, as: .image, record: record)
    }

    // MARK: BREAKPOINT

    func testCreateNSImageBreakpoint() {
        let image = NSImage.breakpoint
        let view = NSImageView(image: image)
        view.appearance = .init(named: .aqua)
        assertSnapshot(matching: view, as: .image, record: record)
    }

    func testCreateNSImageBreakpointFill() {
        let image = NSImage.breakpoint_fill
        let view = NSImageView(image: image)
        view.appearance = .init(named: .aqua)
        assertSnapshot(matching: view, as: .image, record: record)
    }

    func testCreateNSImageGitHub() {
        let image = NSImage.github
        let view = NSImageView(image: image)
        view.appearance = .init(named: .aqua)
        assertSnapshot(matching: view, as: .image, record: record)
    }

    // MARK: - Image Tests

    // MARK: VAULT

    func testCreateImageVault() {
        let image = Image.vault
        let view: NSView = NSHostingController(rootView: image).view
        view.appearance = .init(named: .aqua)
        assertSnapshot(matching: view, as: .image(size: view.intrinsicContentSize), record: record)
    }

    func testCreateImageVaultFill() {
        let image = Image.vault_fill
        let view: NSView = NSHostingController(rootView: image).view
        view.appearance = .init(named: .aqua)
        assertSnapshot(matching: view, as: .image(size: view.intrinsicContentSize), record: record)
    }

    // MARK: COMMIT

    func testCreateImageCommit() {
        let image = Image.commit
        let view: NSView = NSHostingController(rootView: image).view
        view.appearance = .init(named: .aqua)
        assertSnapshot(matching: view, as: .image(size: view.intrinsicContentSize), record: record)
    }

    // MARK: CHECKOUT

    func testCreateImageCheckout() {
        let image = Image.checkout
        let view: NSView = NSHostingController(rootView: image).view
        view.appearance = .init(named: .aqua)
        assertSnapshot(matching: view, as: .image(size: view.intrinsicContentSize), record: record)
    }

    // MARK: BRANCH

    func testCreateImageBranch() {
        let image = Image.branch
        let view: NSView = NSHostingController(rootView: image).view
        view.appearance = .init(named: .aqua)
        assertSnapshot(matching: view, as: .image(size: view.intrinsicContentSize), record: record)
    }

    // MARK: BREAKPOINT

    func testCreateImageBreakpoint() {
        let image = Image.breakpoint
        let view: NSView = NSHostingController(rootView: image).view
        view.appearance = .init(named: .aqua)
        assertSnapshot(matching: view, as: .image(size: view.intrinsicContentSize), record: record)
    }

    func testCreateImageBreakpointFill() {
        let image = Image.breakpoint_fill
        let view: NSView = NSHostingController(rootView: image).view
        view.appearance = .init(named: .aqua)
        assertSnapshot(matching: view, as: .image(size: view.intrinsicContentSize), record: record)
    }

    func testCreateImageGitHub() {
        let image = Image.github
        let view: NSView = NSHostingController(rootView: image).view
        view.appearance = .init(named: .aqua)
        assertSnapshot(matching: view, as: .image(size: view.intrinsicContentSize), record: record)
    }
}
