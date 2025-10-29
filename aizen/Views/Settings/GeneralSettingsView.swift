//
//  GeneralSettingsView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI

struct GeneralSettingsView: View {
    @Binding var defaultEditor: String

    var body: some View {
        Form {
            Section(LocalizedStringKey("settings.general.editor.section")) {
                TextField(LocalizedStringKey("settings.general.editor.command"), text: $defaultEditor)
                    .help(LocalizedStringKey("settings.general.editor.help"))

                Text("settings.general.editor.examples")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
