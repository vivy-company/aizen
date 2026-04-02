import CoreData
import SwiftUI

struct PostCreateActionsSheet: View {
    @ObservedObject var repository: Repository
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showingAddAction = false

    var body: some View {
        VStack(spacing: 0) {
            DetailHeaderBar(showsBackground: false) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Post-Create Actions")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Run automatically after environment creation")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } trailing: {
                Button {
                    showingAddAction = true
                } label: {
                    Label("Add Action", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            Divider()

            PostCreateActionsView(repository: repository, showingAddAction: $showingAddAction)

            Divider()

            HStack {
                Text("Actions run automatically after worktree creation")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 620, height: 620)
        .settingsSheetChrome()
        .environment(\.managedObjectContext, viewContext)
    }
}
