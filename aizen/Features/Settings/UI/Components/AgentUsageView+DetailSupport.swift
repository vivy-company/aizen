import ACP
import Foundation
import SwiftUI

extension AgentUsageDetailContent {
    @ViewBuilder
    var refreshButton: some View {
        switch refreshState {
        case .loading:
            ProgressView()
                .controlSize(.small)
        default:
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh usage")
        }
    }
}
