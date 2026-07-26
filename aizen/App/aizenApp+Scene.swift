//
//  aizenApp+Scene.swift
//  aizen
//
//  Created by OpenAI Codex on 05.04.26.
//

import SwiftUI

extension aizenApp {
    @SceneBuilder
    var appScene: some Scene {
        WindowGroup {
            ReignitionConversationWindow(host: reignitionHost)
                .environmentObject(ghosttyApp)
                .modifier(AppearanceModifier())
                .task {
                    Analytics.shared.recordAppLaunch()
                }
                .task {
                    LicenseStateStore.shared.start()
                }
                .task(
                    id: "\(terminalFontName)\(terminalFontSize)\(terminalThemeName)\(terminalThemeNameLight)\(terminalUsePerAppearanceTheme)\(terminalScrollbackLimitMB)"
                ) {
                    ghosttyApp.reloadConfig()
                    await TmuxSessionRuntime.shared.updateConfig()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1200, height: 800)
        .commands { appCommands }
    }
}
