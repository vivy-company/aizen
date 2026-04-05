//
//  ACPResourceView.swift
//  aizen
//
//  Created by OpenAI Codex on 05.04.26.
//

import Foundation
import SwiftUI
import VVCode

struct ACPResourceView: View {
    let uri: String
    let mimeType: String?
    let text: String?

    private var localPath: String? {
        if uri.hasPrefix("file://"), let url = URL(string: uri) {
            return url.path
        }
        return uri
    }

    private var isCodeFile: Bool {
        if languageHint != nil {
            return true
        }
        if let localPath {
            return VVLanguageBridge.language(fromPath: localPath) != nil
        }
        return VVLanguageBridge.language(fromMIMEType: mimeType) != nil
    }

    private var languageHint: String? {
        if let fromPath = VVLanguageBridge.language(fromPath: localPath)?.identifier {
            return fromPath
        }

        if let fromMime = VVLanguageBridge.language(fromMIMEType: mimeType)?.identifier {
            return fromMime
        }

        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "link")
                    .foregroundStyle(.blue)
                Link(uri, destination: URL(string: uri) ?? URL(fileURLWithPath: "/"))
                    .font(.callout)
                Spacer()
            }

            if let mimeType = mimeType {
                Text(String(format: String(localized: "chat.resource.type"), mimeType))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let text = text {
                Divider()

                if isCodeFile {
                    VVCodeSnippetView(
                        text: text,
                        languageHint: languageHint,
                        filePath: localPath,
                        mimeType: mimeType,
                        maxHeight: 260,
                        showLineNumbers: true,
                        wrapLines: false
                    )
                } else {
                    Text(text)
                        .font(.system(.body, design: .default))
                        .textSelection(.enabled)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.05))
        .cornerRadius(8)
    }
}
