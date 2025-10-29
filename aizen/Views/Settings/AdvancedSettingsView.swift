//
//  AdvancedSettingsView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 27.10.25.
//

import SwiftUI

struct AdvancedSettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showingResetConfirmation = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("settings.advanced.reset.title")
                        .font(.headline)

                    Text("settings.advanced.reset.description")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button(role: .destructive) {
                        showingResetConfirmation = true
                    } label: {
                        Label("settings.advanced.reset.button", systemImage: "trash")
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .formStyle(.grouped)
        .alert(LocalizedStringKey("settings.advanced.reset.alert.title"), isPresented: $showingResetConfirmation) {
            Button(LocalizedStringKey("settings.advanced.reset.alert.cancel"), role: .cancel) {}
            Button(LocalizedStringKey("settings.advanced.reset.alert.confirm"), role: .destructive) {
                resetApp()
            }
        } message: {
            Text("settings.advanced.reset.alert.message")
        }
    }

    private func resetApp() {
        // Clear Core Data
        let entities = ["Workspace", "Repository", "Worktree", "ChatSession", "ChatMessage"]
        for entity in entities {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entity)
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            do {
                try viewContext.execute(deleteRequest)
            } catch {
                print("Failed to delete \(entity): \(error)")
            }
        }

        // Clear UserDefaults
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }

        // Quit app
        NSApplication.shared.terminate(nil)
    }
}

#Preview {
    AdvancedSettingsView()
}
