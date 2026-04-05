//
//  XcodeLogSheetView+Lifecycle.swift
//  aizen
//
//  Created by OpenAI Codex on 06.04.26.
//

import SwiftUI

extension XcodeLogSheetView {
    var sheetBody: some View {
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
            if !buildManager.isLogStreamActive && buildManager.launchedBundleId != nil {
                buildManager.startLogStream()
            }
        }
        .onDisappear {
            buildManager.stopLogStream()
        }
    }
}
