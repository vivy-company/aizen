import Foundation
import SwiftUI

extension AgentCommandEditorSheet {
    func loadCommand() {
        if let command {
            commandName = command.name
            if let fileContent = command.content {
                content = fileContent
                originalContent = fileContent
            }
        } else {
            content = ""
            originalContent = ""
        }
        isLoading = false
    }

    func saveCommand() {
        isSaving = true
        errorMessage = nil

        let name = isNewCommand ? commandName.trimmingCharacters(in: .whitespaces) : (command?.name ?? "")
        let filename = "\(name).md"
        let path = (commandsDirectory as NSString).appendingPathComponent(filename)

        do {
            if !FileManager.default.fileExists(atPath: commandsDirectory) {
                try FileManager.default.createDirectory(
                    atPath: commandsDirectory,
                    withIntermediateDirectories: true
                )
            }

            try content.write(toFile: path, atomically: true, encoding: .utf8)
            originalContent = content
            dismiss()
            onDismiss()
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }

        isSaving = false
    }

    func deleteCommand() {
        guard let command else { return }

        do {
            try FileManager.default.removeItem(atPath: command.path)
            dismiss()
            onDismiss()
        } catch {
            errorMessage = "Failed to delete: \(error.localizedDescription)"
        }
    }
}
