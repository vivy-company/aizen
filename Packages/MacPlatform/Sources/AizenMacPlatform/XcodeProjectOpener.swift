import AppKit
import AizenHost
import Foundation

public struct MacXcodeProjectOpener: XcodeProjectOpening {
    public init() {}

    public func openXcodeProject(at url: URL) async throws {
        guard NSWorkspace.shared.open(url) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: url.path])
        }
    }
}
