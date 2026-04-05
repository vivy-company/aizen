//
//  XcodeLogSheetView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 10.12.25.
//

import SwiftUI

struct XcodeLogSheetView: View {
    @ObservedObject var buildManager: XcodeBuildStore
    @Environment(\.dismiss) var dismiss

    @State var autoScroll = true

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            logContent
            .background(Color(nsColor: .textBackgroundColor))

            Divider()

            footer
        }
        .frame(width: 700, height: 500)
        .onAppear {
            // Auto-start streaming when sheet opens
            if !buildManager.isLogStreamActive && buildManager.launchedBundleId != nil {
                buildManager.startLogStream()
            }
        }
        .onDisappear {
            // Stop streaming when sheet closes
            buildManager.stopLogStream()
        }
    }
}

#Preview {
    XcodeLogSheetView(buildManager: XcodeBuildStore())
}
