//
//  PostCreateActionsView.swift
//  aizen
//

import SwiftUI
import CoreData

struct PostCreateActionsView: View {
    @ObservedObject var repository: Repository
    @Binding var showingAddAction: Bool
    @Environment(\.managedObjectContext) var viewContext
    @StateObject var templateManager = PostCreateTemplateStore.shared

    @State var showingTemplates = false
    @State var editingAction: PostCreateAction?
    @State var showGeneratedScript = false
    @State var pendingTemplate: PostCreateTemplate?

    var actions: [PostCreateAction] {
        get { repository.postCreateActions }
        nonmutating set {
            repository.postCreateActions = newValue
            try? viewContext.save()
        }
    }

    var enabledCount: Int {
        actions.filter(\.enabled).count
    }

    var disabledCount: Int {
        actions.count - enabledCount
    }

    var body: some View {
        Form {
            overviewSection
            configuredActionsSection
            templatesSection

            if !actions.isEmpty {
                advancedSection
            }
        }
        .formStyle(.grouped)
        .settingsSurface()
        .alert("Replace current actions?", isPresented: Binding(
            get: { pendingTemplate != nil },
            set: { newValue in
                if !newValue {
                    pendingTemplate = nil
                }
            }
        )) {
            Button("Cancel", role: .cancel) {
                pendingTemplate = nil
            }
            Button("Replace", role: .destructive) {
                if let pendingTemplate {
                    actions = pendingTemplate.actions
                }
                pendingTemplate = nil
            }
        } message: {
            if let pendingTemplate {
                Text("Applying \"\(pendingTemplate.name)\" will replace the current action list.")
            }
        }
        .sheet(isPresented: $showingAddAction) {
            PostCreateActionEditorSheet(
                action: nil,
                onSave: { action in
                    actions = actions + [action]
                },
                onCancel: {},
                repositoryPath: repository.path
            )
        }
        .sheet(item: $editingAction) { action in
            PostCreateActionEditorSheet(
                action: action,
                onSave: { updated in
                    var updatedActions = actions
                    if let index = updatedActions.firstIndex(where: { $0.id == updated.id }) {
                        updatedActions[index] = updated
                        actions = updatedActions
                    }
                },
                onCancel: {},
                repositoryPath: repository.path
            )
        }
        .sheet(isPresented: $showingTemplates) {
            PostCreateTemplatesSheet(
                onSelect: { template in
                    applyTemplate(template)
                }
            )
        }
    }

    func moveAction(from index: Int, direction: Int) {
        let destination = index + direction
        guard actions.indices.contains(index), actions.indices.contains(destination) else { return }
        var updatedActions = actions
        let item = updatedActions.remove(at: index)
        updatedActions.insert(item, at: destination)
        actions = updatedActions
    }

    func removeAction(at index: Int) {
        guard actions.indices.contains(index) else { return }
        var updatedActions = actions
        updatedActions.remove(at: index)
        actions = updatedActions
    }

    private func applyTemplate(_ template: PostCreateTemplate) {
        if actions.isEmpty {
            actions = template.actions
        } else {
            pendingTemplate = template
        }
    }
}
