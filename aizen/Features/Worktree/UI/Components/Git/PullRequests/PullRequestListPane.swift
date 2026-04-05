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

    @Environment(\.controlActiveState) var controlActiveState
    @ObservedObject var viewModel: PullRequestsViewModel
    @State var hoveredPullRequestID: Int?
}
