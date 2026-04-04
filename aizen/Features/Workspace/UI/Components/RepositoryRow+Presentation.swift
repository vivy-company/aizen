import SwiftUI

private struct RepositoryRowPresentationModifier: ViewModifier {
    @Binding var showingRemoveConfirmation: Bool
    @Binding var alsoDeleteFromFilesystem: Bool
    @Binding var showingNoteEditor: Bool
    @Binding var showingPostCreateActions: Bool

    let repository: Repository
    let repositoryManager: WorkspaceRepositoryStore
    let removeRepository: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showingRemoveConfirmation) {
                RepositoryRemoveSheet(
                    repositoryName: repository.name ?? String(localized: "workspace.repository.unknown"),
                    alsoDeleteFromFilesystem: $alsoDeleteFromFilesystem,
                    onCancel: {
                        showingRemoveConfirmation = false
                        alsoDeleteFromFilesystem = false
                    },
                    onRemove: {
                        showingRemoveConfirmation = false
                        removeRepository()
                    }
                )
            }
            .sheet(isPresented: $showingNoteEditor) {
                NoteEditorView(
                    note: Binding(
                        get: { repository.note ?? "" },
                        set: { repository.note = $0 }
                    ),
                    title: String(localized: "repository.note.title \(repository.name ?? "")"),
                    onSave: {
                        try? repositoryManager.updateRepositoryNote(repository, note: repository.note)
                    }
                )
            }
            .sheet(isPresented: $showingPostCreateActions) {
                PostCreateActionsSheet(repository: repository)
            }
    }
}

extension View {
    func repositoryRowPresentation(view: RepositoryRow) -> some View {
        modifier(
            RepositoryRowPresentationModifier(
                showingRemoveConfirmation: view.$showingRemoveConfirmation,
                alsoDeleteFromFilesystem: view.$alsoDeleteFromFilesystem,
                showingNoteEditor: view.$showingNoteEditor,
                showingPostCreateActions: view.$showingPostCreateActions,
                repository: view.repository,
                repositoryManager: view.repositoryManager,
                removeRepository: view.removeRepository
            )
        )
    }
}
