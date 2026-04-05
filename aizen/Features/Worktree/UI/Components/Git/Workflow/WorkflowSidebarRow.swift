import SwiftUI

struct WorkflowSidebarRow: View {
    let workflow: Workflow
    let isSelected: Bool
    let onSelect: () -> Void
    let onTrigger: (Workflow) -> Void

    @Environment(\.controlActiveState) var controlActiveState
    @State var isHovered: Bool = false
    @State var isButtonHovered: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bolt.horizontal.circle")
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? selectedHighlightColor : .secondary)
                .frame(width: 22, alignment: .top)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(workflow.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSelected ? selectedHighlightColor : .primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer()

                    if workflow.state != .active {
                        Text(workflow.state.rawValue)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    Text(workflow.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if workflow.canTrigger {
                        Text("•")
                            .foregroundStyle(Color.secondary.opacity(0.45))

                        Text("manual")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .padding(.trailing, workflow.canTrigger ? 40 : 0)
        .overlay(alignment: .trailing) {
            if workflow.canTrigger {
                Button {
                    onTrigger(workflow)
                } label: {
                    triggerButtonIcon
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isButtonHovered = hovering
                }
                .help(String(localized: "git.workflow.run"))
                .padding(.trailing, 10)
            }
        }
        .background(backgroundFill)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
