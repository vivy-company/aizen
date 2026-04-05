//
//  RepositoryAddSheet+Shell.swift
//  aizen
//
//  Created by OpenAI Codex on 06.04.26.
//

import SwiftUI

extension RepositoryAddSheet {
    var sheetContent: some View {
        VStack(spacing: 0) {
            DetailHeaderBar(showsBackground: false) {
                Text("repository.add.title", bundle: .main)
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            Divider()

            Form { formContent }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)

            Divider()

            HStack {
                Spacer()

                Button(String(localized: "general.cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(actionButtonText) {
                    addRepository()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing || !isValid)
            }
            .padding()
        }
        .frame(width: 520)
        .frame(minHeight: 360, maxHeight: 560)
        .settingsSheetChrome()
    }
}
