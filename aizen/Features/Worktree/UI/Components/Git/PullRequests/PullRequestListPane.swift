//
//  PullRequestListPane.swift
//  aizen
//
//  Left pane showing list of PRs with filter and pagination
//

import SwiftUI

struct PullRequestListPane: View {
    enum Layout {
        static let headerHorizontalPadding: CGFloat = 12
        static let headerVerticalPadding: CGFloat = 8
        static let chipCornerRadius: CGFloat = 9
        static let listBottomPadding: CGFloat = 8
    }

    @Environment(\.controlActiveState) private var controlActiveState
    @ObservedObject var viewModel: PullRequestsViewModel
    @State var hoveredPullRequestID: Int?

    var selectedForegroundColor: Color {
        controlActiveState == .key ? .accentColor : .accentColor.opacity(0.78)
    }

    var selectionFillColor: Color {
        let base = NSColor.unemphasizedSelectedContentBackgroundColor
        let alpha: Double = controlActiveState == .key ? 0.26 : 0.18
        return Color(nsColor: base).opacity(alpha)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            GitWindowDivider()
            listContent
        }
    }

}
