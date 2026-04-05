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
        sheetBody
    }
}

#Preview {
    XcodeLogSheetView(buildManager: XcodeBuildStore())
}
