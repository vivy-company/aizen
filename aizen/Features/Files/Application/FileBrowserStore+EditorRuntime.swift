//
//  FileBrowserStore+EditorRuntime.swift
//  aizen
//
//  Per-open-file editor runtime caching.
//

import Foundation

extension FileBrowserStore {
    func editorRuntime(for file: OpenFileInfo) -> CodeEditorRuntime {
        if let existingRuntime = editorRuntimesByFileId[file.id] {
            return existingRuntime
        }

        let runtime = CodeEditorRuntime(
            content: file.content,
            language: editorLanguage(for: file.path)
        )
        editorRuntimesByFileId[file.id] = runtime
        return runtime
    }

    func removeEditorRuntime(id: UUID) {
        editorRuntimesByFileId[id]?.clearGitDiff()
        editorRuntimesByFileId.removeValue(forKey: id)
    }

    private func editorLanguage(for path: String) -> String? {
        let ext = (path as NSString).pathExtension.lowercased()
        return ext.isEmpty ? nil : ext
    }
}
