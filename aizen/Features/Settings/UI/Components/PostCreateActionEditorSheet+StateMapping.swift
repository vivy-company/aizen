import Foundation
import SwiftUI

extension PostCreateActionEditorSheet {
    var isValid: Bool {
        switch selectedType {
        case .copyFiles:
            return !selectedFiles.isEmpty
        case .runCommand:
            return !command.trimmingCharacters(in: CharacterSet.whitespaces).isEmpty
        case .symlink:
            return !symlinkSource.trimmingCharacters(in: CharacterSet.whitespaces).isEmpty
        case .customScript:
            return !customScript.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
        }
    }

    var effectiveSymlinkTarget: String {
        symlinkTarget.isEmpty ? symlinkSource : symlinkTarget
    }

    func loadAction(_ action: PostCreateAction) {
        selectedType = action.type
        switch action.config {
        case .copyFiles(let config):
            selectedFiles = Set(config.patterns)
        case .runCommand(let config):
            command = config.command
            workingDirectory = config.workingDirectory
        case .symlink(let config):
            symlinkSource = config.source
            symlinkTarget = config.target
        case .customScript(let config):
            customScript = config.script
        }
    }

    func saveAction() {
        let config: ActionConfig
        switch selectedType {
        case .copyFiles:
            config = .copyFiles(CopyFilesConfig(patterns: Array(selectedFiles).sorted()))
        case .runCommand:
            config = .runCommand(
                RunCommandConfig(command: command, workingDirectory: workingDirectory)
            )
        case .symlink:
            config = .symlink(
                SymlinkConfig(source: symlinkSource, target: effectiveSymlinkTarget)
            )
        case .customScript:
            config = .customScript(CustomScriptConfig(script: customScript))
        }

        let newAction = PostCreateAction(
            id: action?.id ?? UUID(),
            type: selectedType,
            enabled: action?.enabled ?? true,
            config: config
        )

        onSave(newAction)
        dismiss()
    }
}
