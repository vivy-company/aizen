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

            errorBanner

            Divider()

            footerView
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
