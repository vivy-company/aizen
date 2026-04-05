//
//  XcodeDestinationPicker.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 10.12.25.
//

import SwiftUI

struct XcodeDestinationPicker: View {
    @ObservedObject var buildManager: XcodeBuildStore

    var body: some View {
        Menu {
            if let project = buildManager.detectedProject, project.schemes.count > 1 {
                schemeSection(project: project)
                Divider()
            }

            destinationSections
        } label: {
            menuLabel
        }
        .buttonStyle(.borderless)
        .padding(8)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(buildManager.currentPhase.isBuilding)
    }
}

#Preview {
    XcodeDestinationPicker(buildManager: XcodeBuildStore())
        .padding()
}
