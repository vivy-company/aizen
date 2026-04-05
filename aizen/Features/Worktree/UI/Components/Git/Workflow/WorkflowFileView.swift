//
//  WorkflowFileView.swift
//  aizen
//
//  Displays workflow YAML file content in code editor
//

import SwiftUI

struct WorkflowFileView: View {
    let workflow: Workflow
    let worktreePath: String

    @State var fileContent: String = ""
    @State var isLoading: Bool = true
    @State var error: String?

    @AppStorage("editorFontFamily") private var editorFontFamily: String = "Menlo"
    @AppStorage("editorFontSize") private var editorFontSize: Double = 12

    var body: some View {
        VStack(spacing: 0) {
            header

            GitWindowDivider()

            if isLoading {
                loadingView
            } else if let error = error {
                errorView(error)
            } else {
                codeEditor
            }
        }
        .onAppear {
            loadFile()
        }
    }
}
