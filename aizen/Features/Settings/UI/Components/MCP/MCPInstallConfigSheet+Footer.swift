//
//  MCPInstallConfigSheet+Footer.swift
//  aizen
//
//  Footer and error presentation for MCP server installation
//

import SwiftUI

extension MCPInstallConfigSheet {
    @ViewBuilder
    var errorBanner: some View {
        if let error = errorMessage {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.red.opacity(0.1))
        }
    }

    var footerView: some View {
        HStack {
            Spacer()

            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button {
                Task { await install() }
            } label: {
                if isInstalling {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Add")
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(!canInstall || isInstalling)
        }
        .padding()
        .background(AppSurfaceTheme.backgroundColor())
    }
}
