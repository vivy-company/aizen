//
//  AttachmentReviewAndBuildDetailViews.swift
//  aizen
//

import SwiftUI

struct ReviewCommentsDetailView: View {
    let content: String
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            DetailHeaderBar(showsBackground: false) {
                Text("Review Comments")
                    .font(.headline)
            } trailing: {
                DetailDoneButton {
                    dismiss()
                }
            }

            Divider()

            ScrollView {
                MarkdownView(content: content)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .frame(width: 500, height: 400)
    }
}

struct BuildErrorDetailView: View {
    let content: String
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            DetailHeaderBar(showsBackground: false) {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                    Text("Build Error")
                        .font(.headline)
                }
            } trailing: {
                DetailDoneButton {
                    dismiss()
                }
            }

            Divider()

            TextDetailBody(
                text: content,
                font: .system(size: 11, design: .monospaced),
                showsBackground: true
            )
        }
        .frame(width: 600, height: 400)
    }
}
