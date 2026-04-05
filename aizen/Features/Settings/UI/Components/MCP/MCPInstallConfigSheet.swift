//
//  MCPInstallConfigSheet.swift
//  aizen
//
//  Configuration sheet for MCP server installation
//

import SwiftUI

struct MCPInstallConfigSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var mcpManager = MCPManagementStore.shared

    let server: MCPServer
    let agentId: String
    let agentName: String
    let onInstalled: () -> Void

    @State var selectedPackageIndex = 0
    @State var selectedRemoteIndex = 0
    @State var installType: InstallType = .package
    @State var envValues: [String: String] = [:]
    @State var showSecrets: Set<String> = []
    @State var isInstalling = false
    @State var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            headerView

            Divider()

            contentView

            // Error message
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

            Divider()

            // Footer
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
        .frame(width: 520, height: 520)
        .settingsSheetChrome()
        .onAppear {
            MCPInstallConfigSupport.setupInitialState(
                hasPackages: hasPackages,
                hasRemotes: hasRemotes,
                selectedPackage: selectedPackage,
                installType: &installType,
                envValues: &envValues
            )
        }
    }

}
