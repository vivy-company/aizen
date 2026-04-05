//
//  aizenApp+Scene.swift
//  aizen
//
//  Created by OpenAI Codex on 05.04.26.
//

import SwiftUI

extension aizenApp {
    var appScene: some Scene {
        WindowGroup {
            RootView(context: persistenceController.container.viewContext)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(ghosttyApp)
                .modifier(AppearanceModifier())
                .task {
                    LicenseStateStore.shared.start()
                }
                .task(id: "\(terminalFontName)\(terminalFontSize)\(terminalThemeName)\(terminalThemeNameLight)\(terminalUsePerAppearanceTheme)") {
                    ghosttyApp.reloadConfig()
                    await TmuxSessionRuntime.shared.updateConfig()
                }
                .task {
                    await cleanupOrphanedTmuxSessions()
                }
                .task {
                    await ChatSessionPersistence.shared.backfillSessionMetadata(
                        in: persistenceController.container.viewContext
                    )
                }
                .task {
                    await ChatSessionPersistence.shared.recoverDetachedSessionsFromLegacyScope(
                        in: persistenceController.container.viewContext
                    )
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1200, height: 800)
        .commands { appCommands }
    }
}
